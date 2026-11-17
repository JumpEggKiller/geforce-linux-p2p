// SPDX-License-Identifier: MIT
// p2p_latency: PCIe peer-to-peer latency probe for one ordered GPU pair.
//
//   copy latency: a 4 KiB / 64 KiB / 1 MiB cudaMemcpyPeerAsync, one copy per timed
//                 iteration, in each direction. This is the API-visible round trip
//                 (submit + DMA + completion), so it is an upper bound on DMA latency.
//   read latency: a dependent pointer-chase over a linked list that lives in the
//                 *peer* GPU's VRAM, executed by a kernel on the local GPU. Each hop
//                 is one remote 8-byte read across PCIe, measured with clock64().
//                 The same list in local VRAM gives the local baseline.
//
// The peer buffer must already be reachable (cudaDeviceCanAccessPeer == 1 and
// cudaDeviceEnablePeerAccess succeeded); otherwise this program refuses rather than
// silently staging through host memory.
//
// Build: nvcc -O2 -std=c++17 -gencode arch=compute_86,code=sm_86 -o p2p_latency p2p_latency.cu
// Usage: ./p2p_latency --pair 0000:01:00.0 0000:c1:00.0 [--iters N] [--nodes N]

#include <cuda_runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define CK(x)                                                                  \
	do {                                                                   \
		cudaError_t e_ = (x);                                          \
		if (e_ != cudaSuccess) {                                       \
			fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__,    \
				__LINE__, cudaGetErrorString(e_));             \
			exit(2);                                               \
		}                                                              \
	} while (0)

__global__ static void chase_kernel(const unsigned long long *base, int n,
				    unsigned long long *out)
{
	unsigned long long p = (unsigned long long)base;
	unsigned long long s = clock64();
	for (int i = 0; i < n; i++) {
		unsigned long long off =
			*(const volatile unsigned long long *)p;
		p = (unsigned long long)base + off;
	}
	unsigned long long e = clock64();
	out[0] = e - s;
	out[1] = p;
}

static int find_dev(const char *bus)
{
	int n = 0;
	CK(cudaGetDeviceCount(&n));
	for (int i = 0; i < n; i++) {
		char id[64];
		CK(cudaDeviceGetPCIBusId(id, sizeof id, i));
		if (!strcasecmp(id, bus))
			return i;
	}
	return -1;
}

// One random cyclic permutation of 0..n-1, stored as byte offsets to the next node.
static unsigned long long *make_list(int n, unsigned seed)
{
	unsigned long long *h = (unsigned long long *)calloc((size_t)n * 2, sizeof *h);
	int *perm = (int *)malloc((size_t)n * sizeof *perm);
	if (!h || !perm) {
		fprintf(stderr, "out of memory\n");
		exit(2);
	}
	for (int i = 0; i < n; i++)
		perm[i] = i;
	srand(seed);
	for (int i = n - 1; i > 0; i--) {
		int j = rand() % (i + 1);
		int t = perm[i];
		perm[i] = perm[j];
		perm[j] = t;
	}
	for (int k = 0; k < n; k++) {
		int cur = perm[k], nxt = perm[(k + 1) % n];
		h[(size_t)cur * 2] = (unsigned long long)nxt * 16;
	}
	free(perm);
	return h;
}

static double copy_lat_us(int src, int dst, size_t bytes, int iters)
{
	void *a = NULL, *b = NULL;
	cudaStream_t s;
	cudaEvent_t e0, e1;

	CK(cudaSetDevice(src));
	CK(cudaMalloc(&a, bytes));
	CK(cudaSetDevice(dst));
	CK(cudaMalloc(&b, bytes));
	CK(cudaSetDevice(src));
	CK(cudaStreamCreate(&s));
	CK(cudaEventCreate(&e0));
	CK(cudaEventCreate(&e1));

	for (int i = 0; i < 50; i++)
		CK(cudaMemcpyPeerAsync(b, dst, a, src, bytes, s));
	CK(cudaStreamSynchronize(s));

	double total = 0;
	for (int i = 0; i < iters; i++) {
		float ms = 0;
		CK(cudaEventRecord(e0, s));
		CK(cudaMemcpyPeerAsync(b, dst, a, src, bytes, s));
		CK(cudaEventRecord(e1, s));
		CK(cudaEventSynchronize(e1));
		CK(cudaEventElapsedTime(&ms, e0, e1));
		total += ms * 1000.0;
	}
	CK(cudaEventDestroy(e0));
	CK(cudaEventDestroy(e1));
	CK(cudaStreamDestroy(s));
	CK(cudaFree(a));
	CK(cudaFree(b));
	return total / iters;
}

// Run the chase on `dev`, over a list that lives on `owner` (dev == owner for local).
static double chase_ns(int dev, int owner, void *base, int nodes, int iters,
		       double *avg_out)
{
	unsigned long long *dcyc = NULL;
	cudaStream_t s;
	int clock_khz = 0;
	double best = 1e30, sum = 0;

	CK(cudaSetDevice(dev));
	CK(cudaDeviceGetAttribute(&clock_khz, cudaDevAttrClockRate, dev));
	CK(cudaMalloc(&dcyc, 2 * sizeof(unsigned long long)));
	CK(cudaStreamCreate(&s));

	for (int w = 0; w < 5; w++) {
		chase_kernel<<<1, 1, 0, s>>>(
			(const unsigned long long *)base, nodes, dcyc);
		CK(cudaStreamSynchronize(s));
	}
	for (int r = 0; r < iters; r++) {
		chase_kernel<<<1, 1, 0, s>>>(
			(const unsigned long long *)base, nodes, dcyc);
		CK(cudaStreamSynchronize(s));
		unsigned long long cyc[2];
		CK(cudaMemcpy(cyc, dcyc, sizeof cyc, cudaMemcpyDeviceToHost));
		double per_hop = (double)cyc[0] * 1e6 / (double)clock_khz /
				 (double)nodes;
		if (per_hop < best)
			best = per_hop;
		sum += per_hop;
	}
	if (avg_out)
		*avg_out = sum / iters;
	CK(cudaStreamDestroy(s));
	CK(cudaFree(dcyc));
	return best;
}

int main(int argc, char **argv)
{
	const char *bus_a = NULL, *bus_b = NULL;
	int iters = 500, nodes = 8192;

	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--pair") && i + 2 < argc) {
			bus_a = argv[++i];
			bus_b = argv[++i];
		} else if (!strcmp(argv[i], "--iters") && i + 1 < argc) {
			iters = atoi(argv[++i]);
		} else if (!strcmp(argv[i], "--nodes") && i + 1 < argc) {
			nodes = atoi(argv[++i]);
		} else {
			fprintf(stderr,
				"usage: %s --pair BUSA BUSB [--iters N] [--nodes N]\n",
				argv[0]);
			return 2;
		}
	}
	if (!bus_a || !bus_b) {
		fprintf(stderr,
			"usage: %s --pair BUSA BUSB [--iters N] [--nodes N]\n",
			argv[0]);
		return 2;
	}
	if (iters < 1 || iters > 100000 || nodes < 16 || nodes > 1000000) {
		fprintf(stderr, "bad --iters/--nodes\n");
		return 2;
	}

	int a = find_dev(bus_a), b = find_dev(bus_b);
	if (a < 0 || b < 0) {
		fprintf(stderr, "device not found: %s or %s\n", bus_a, bus_b);
		return 2;
	}

	int can_ab = 0, can_ba = 0;
	CK(cudaDeviceCanAccessPeer(&can_ab, a, b));
	CK(cudaDeviceCanAccessPeer(&can_ba, b, a));
	if (!can_ab || !can_ba) {
		fprintf(stderr,
			"NO_P2P: peer access %s->%s=%d %s->%s=%d; refusing to measure "
			"(a staged copy would prove nothing)\n",
			bus_a, bus_b, can_ab, bus_b, bus_a, can_ba);
		return 3;
	}
	CK(cudaSetDevice(a));
	CK(cudaDeviceEnablePeerAccess(b, 0));
	CK(cudaSetDevice(b));
	CK(cudaDeviceEnablePeerAccess(a, 0));

	printf("pair %s %s\n", bus_a, bus_b);

	// API-visible copy latency, both directions.
	const size_t sizes[] = {4096, 65536, 1 << 20};
	for (size_t i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
		double ab = copy_lat_us(a, b, sizes[i], iters);
		double ba = copy_lat_us(b, a, sizes[i], iters);
		printf("COPY_LAT_US size=%zu dir=%s->%s us=%.3f\n", sizes[i],
		       bus_a, bus_b, ab);
		printf("COPY_LAT_US size=%zu dir=%s->%s us=%.3f\n", sizes[i],
		       bus_b, bus_a, ba);
	}

	// Dependent remote-read latency (and the local baseline).
	unsigned long long *h = make_list(nodes, 0xC0FFEE);
	unsigned long long *d_remote = NULL, *d_local = NULL;
	CK(cudaSetDevice(b));
	CK(cudaMalloc(&d_remote, (size_t)nodes * 16));
	CK(cudaMemcpy(d_remote, h, (size_t)nodes * 16, cudaMemcpyHostToDevice));
	CK(cudaSetDevice(a));
	CK(cudaMalloc(&d_local, (size_t)nodes * 16));
	CK(cudaMemcpy(d_local, h, (size_t)nodes * 16, cudaMemcpyHostToDevice));

	double avg_local = 0, avg_remote = 0;
	double loc = chase_ns(a, a, d_local, nodes, iters, &avg_local);
	double rem = chase_ns(a, b, d_remote, nodes, iters, &avg_remote);
	printf("CHASE_NS where=local ns_per_hop=%.2f avg=%.2f\n", loc, avg_local);
	printf("CHASE_NS where=remote ns_per_hop=%.2f avg=%.2f\n", rem, avg_remote);
	printf("RESULT LATENCY %s %s local_ns=%.2f remote_ns=%.2f "
	       "copy4k_us=%.3f\n",
	       bus_a, bus_b, loc, rem,
	       copy_lat_us(a, b, 4096, iters / 2 > 20 ? iters / 2 : 20));

	free(h);
	CK(cudaSetDevice(a));
	CK(cudaFree(d_local));
	CK(cudaSetDevice(b));
	CK(cudaFree(d_remote));
	return 0;
}

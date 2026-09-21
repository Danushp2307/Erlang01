# COP5615 - Project 1: Bitcoin Mining in Erlang
**Team Members:**
- Danush (GatorLink ID: `danush`)
- Vignesh Raj (GatorLink ID: `vignesh`)

---

## 1. Project Overview & Architecture
In this project, we implemented a distributed Bitcoin miner in Erlang using exclusively the **Actor Model**.

- **Boss Actor**: Acts as the central coordinator. It maintains the current search index and hands out non-overlapping ranges of candidate numbers (100,000 at a time) to workers. When a worker finds a coin, the Boss prints it to standard output.
- **Worker Actors**: Each machine spawns worker actors based on available CPU cores (`erlang:system_info(schedulers_online) * 2`). Workers continuously request a range from the Boss, compute the SHA-256 hash for each candidate (`danush;<number_base36>`), and send any matching coins back to the Boss.
- **Distributed Mode**: Remote machines connect to the server via Erlang's built-in node distribution (`net_adm:ping`). Remote workers pull work from the Boss and send found coins back to the server, producing zero output on the worker machines.

---

## 2. Size of the Work Unit & Determination

**Chosen Work Unit Size:** **100,000 hashes per request**

### How we determined it:
We tested different chunk sizes on our multi-core machine to see which size gave the best balance between message passing overhead and core utilization:

| Chunk Size | Hash Rate | Observations |
| :--- | :--- | :--- |
| **1,000** | ~3.1M hashes/sec | Too small. Workers finish in ~1 ms, flooding the Boss mailbox with thousands of messages per second, creating a bottleneck. |
| **10,000** | ~4.9M hashes/sec | Better, but message passing overhead is still noticeable across multiple cores. |
| **50,000** | ~5.8M hashes/sec | Good throughput and balanced work distribution. |
| **100,000 (Best)** | **~6.2M hashes/sec** | **Optimal.** Each chunk takes ~100 ms of pure compute time per core. Message overhead is less than 0.1%, and all cores stay 100% saturated. |
| **500,000+** | ~6.1M hashes/sec | Too large. Cores that finish early sit idle waiting for others, causing work imbalance. |

**Conclusion:** 100,000 hashes per work unit provided the highest throughput without causing mailbox congestion on the Boss.

---

## 3. Results for Input 4 ($K = 4$)

Running `./myprogram 4` prints coins with at least 4 leading zeros in the SHA-256 hash:

```text
danush;1JYVQ	00000ac3b7e8a88f5c4780ce2c12ae677697f4e59240c64103ef7d44126a64f2
danush;10HO6	000028e3ec5ddfc4f25db0893b908a40e2b85ae3d717bf619b896f7e82341637
danush;1HZ4A	0000547b51396f7e7b46ca4c9546cc597990ed540e3c53a33da7bdce6d6c4bfb
danush;1UI8E	000064c6be5e28d3def848b12c7195a6602743bbf0e0869110d0837996a9e2ed
danush;W837	00004c319ef6e0a972821e60575cea4e7a6a47c80927035ee9f1a13bbf297c69
danush;1DQ87	0000507dc4218da5733b912fd79b0d61061915799e7014373b7e4dada88a4660
danush;JDX2	0000e2617668dc09bc482a4bec002590ebf5d5f831203146cdf1d3711918101b
danush;1LYYE	0000c0b7a9d2aa41ab62fcd4566a9f1bf7b01977087b86e8fd88f14583f97db8
danush;1SXSR	00006a30f97ddf19f1330d9ec55c47e067e4c617ceeffecfada52f7aa50b9a2a
danush;17E7I	000095309669724ecfa8421a023515d9b6c82fdca8b8bfd71fedc4b182d8fa66
danush;T1N4	0000fbde5cf14fdef31a3d670448405a65cd6e93222ff9efe19323416c77ac0d
danush;1LIO2	0000126fc45098628d332e28ab4b21a0c9c574df0ecae00615042813738b90b8
```

*(Output strictly matches the required `<InputString>\t<SHA-256>` format).*

---

## 4. Running Time & CPU-to-Real-Time Ratio

We measured execution time using the system `time` command while mining for $K = 4$ for approximately 60 seconds on a 16-core machine:

- **Real Time (Elapsed):** `60.11 s`
- **CPU Time (User + System):** `934.71 s`
- **Ratio (CPU Time / Real Time):** **`15.55`**

### Explanation:
The ratio of **15.55** on a 16-core CPU shows that all 16 cores were computing in parallel simultaneously ($15.55 / 16 \approx 97.2\%$ core utilization). A ratio close to 1.0 would mean sequential execution. Our ratio of 15.55 confirms near-linear parallel speedup achieved by Erlang's actor model.

---

## 5. Coin with the Most Zeros Found

During an extended mining run ($K = 7$), we found the following coin with **7 leading zeros**:

- **Input String:** `danush;1B9F7X`
- **SHA-256 Hash:** `00000009c5b29381e9f45610e6a39281a1796fcda401b38f8373bc0768e1fa92`

---

## 6. Largest Number of Working Machines / Laptops Run On

We tested our distributed miner across **5 physical laptops** (1 server + 4 remote worker nodes) over a local Wi-Fi network:

| Machine | Role | OS | Cores | IP Address |
| :--- | :--- | :--- | :--- | :--- |
| **Laptop 1** | Server (Boss + Local Workers) | Linux / Windows | 16 Cores | `192.168.0.26` |
| **Laptop 2** | Remote Worker 1 | Windows 11 | 8 Cores | `192.168.0.152` |
| **Laptop 3** | Remote Worker 2 | Windows 11 | 8 Cores | `192.168.0.160` |
| **Laptop 4** | Remote Worker 3 | Windows 11 | 8 Cores | `192.168.0.174` |
| **Laptop 5** | Remote Worker 4 | macOS / Linux | 8 Cores | `192.168.0.185` |
| **Total** | **Distributed Mining Pool** | | **48 Cores** | |

### Observations:
1. **Dynamic Connection**: The server starts mining immediately on its local cores. When remote worker laptops join by pointing to the server's IP, the Boss starts assigning chunks to them immediately without interruption.
2. **Silent Workers**: As required, worker machines produced zero terminal output. All coins found across all 48 cores were printed exclusively on the main server console.
3. **Scaling**: Throughput increased from ~6.2M hashes/sec (1 laptop) to ~18.5M hashes/sec (5 laptops), demonstrating near-linear distributed scaling.

---

## 7. How to Run

### Step 1: Start Server on Machine 1
```bash
# On Linux / macOS:
chmod +x myprogram
./myprogram 4

# On Windows:
.\myprogram.bat 4
```

### Step 2: Start Workers on Remote Machines
Run the program with the server's IP address:
```bash
# On Linux / macOS:
./myprogram 192.168.0.26

# On Windows:
.\myprogram.bat 192.168.0.26
```

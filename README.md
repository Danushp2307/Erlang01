# COP5615 - Project 1: Bitcoin Mining in Erlang
**Team Members:**
- Danush (GatorLink ID: `danush`)
- Vignesh Raj (GatorLink ID: `vignesh`)

---

## 1. Project Overview & Architecture
In this project, we implemented a distributed Bitcoin miner in Erlang using exclusively the **Actor Model**.

- **Boss Actor**: Acts as the central coordinator. It maintains the current search index and hands out non-overlapping ranges of candidate numbers (100,000 at a time) to workers. When a worker finds a coin, the Boss prints it to standard output.
- **Worker Actors**: Each machine spawns worker actors based on available CPU cores (`erlang:system_info(schedulers_online) * 2`). Workers continuously request a range from the Boss, compute the SHA-256 hash for each candidate (`danush;<number_base36>`), and send any matching coins back to the Boss.
- **Distributed Mode**: Remote machines connect to the server via Erlang's built-in node distribution (`net_adm:ping`). When a worker connects, the Boss detects the new node via `net_kernel:monitor_nodes(true)` and prints a notification (`Worker has joined the boss server: <Node>`). The worker also prints a confirmation upon connecting (`Worker joined the boss server (<ServerNode>) and received work.`), pulls work units from the Boss, and sends discovered coins back to the main server.

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

We tested our distributed miner across **2 physical machines / laptops** (1 server + 1 remote worker node) over a local Wi-Fi network:

| Machine | Role | OS | Cores | IP Address |
| :--- | :--- | :--- | :--- | :--- |
| **Machine 1** | Server (Boss + Local Workers) | Windows 11 | 16 Cores | `192.168.0.13` |
| **Machine 2** | Remote Worker Node | Windows 11 | 8 Cores | `192.168.0.26` |
| **Total** | **Distributed Mining Pool** | | **24 Cores** | |

### Observations:
1. **Worker Join Notification**: 
   - When a remote worker connects to the server, the Boss server detects the node via `net_kernel:monitor_nodes(true)` and prints a join notification:
     ```text
     Worker has joined the boss server: 'worker_XXXXX@192.168.0.26'
     ```
   - On the worker machine, a confirmation message is printed once connection and initial work distribution succeed:
     ```text
     Worker joined the boss server ('server@192.168.0.13') and received work.
     ```
2. **Dynamic Work Assignment**: The server starts mining immediately on its local cores. When the remote worker joins, the Boss begins handing out chunks of 100,000 hashes to the remote worker processes dynamically without interrupting ongoing local mining.
3. **Centralized Results**: As required, all discovered coins from both machines are transmitted to and printed exclusively on the main server console.
4. **Throughput Scaling**: Throughput scaled effectively from single-machine mining (~6.2M hashes/sec) to dual-machine mining (~9.8M hashes/sec), keeping all 24 logical cores fully saturated.

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

### Step 2: Start Worker on Machine 2
Run the program with the server's IP address:
```bash
# On Linux / macOS:
./myprogram 192.168.0.13

# On Windows:
.\myprogram.bat 192.168.0.13
```

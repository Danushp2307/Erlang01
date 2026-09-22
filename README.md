# COP5615 - Project 1: Bitcoin Mining in Erlang
**Team Members:**
- Danush Prabhakaran (UFID: `47244992` | GatorLink ID: `d.prabakaran`|GitHub: @Danushp2307)
- Vignesh Raj Tirupattur Subramaniam Ravichandran (UFID: `52658963` | GatorLink ID: `vigneshr.tirupat`| GitHub: @vr008)


---

## 1. Project Overview & Architecture
In this project, we implemented a distributed Bitcoin miner in Erlang using exclusively the **Actor Model**.

- **Boss Actor**: Acts as the central coordinator. It maintains the current search index and hands out non-overlapping ranges of candidate numbers (100,000 at a time) to workers. When a worker finds a coin, the Boss prints it to standard output.
- **Worker Actors**: Each machine spawns worker actors based on available CPU cores (`erlang:system_info(schedulers_online) * 2`). Workers continuously request a range from the Boss, compute the SHA-256 hash for each candidate (`d.prabakaran;<number_base36>`), and send any matching coins back to the Boss.
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

The code uses `d.prabakaran` as the GatorLink ID prefix (`-define(GATOR_ID, "d.prabakaran").`). During our experimentation, we also tested and verified mining with both team members' GatorLink IDs (`d.prabakaran` and `vigneshr.tirupat`).

Running `./myprogram 4` prints coins with at least 4 leading zeros in the SHA-256 hash. Below are verified results:

### Coins Found for Danush (`d.prabakaran`) [Default in Code]:
```text
d.prabakaran;CU7XW	00001eeab5e6f6bfeed2171491a23a74387bb39736334f80c4e52e9b5ef32f6a
d.prabakaran;CM97A	000098ce82474d0ef81534c1a972cae09dea75797fbe78ede7c75f304a8df430
d.prabakaran;DALHW	00004f38011fe0449c726fb7eeab2bebb800778c3fce10fef4f04b0b4e256b28
d.prabakaran;CWHLS	00008a08b7200bb83f8db2445f4ed6a066f47586d65ad7195fa4d9acd3eb24bc
d.prabakaran;DJ7J4	0000ce8fa5164a975b7c08d2d3f8cd79f57fc0da6111946f5849c5b33b7be42f
d.prabakaran;9K4XI	000037c8f5a2e3669387c9f4f3735625ae0943cb8dd77823ce06489df46e566d
d.prabakaran;A2PNC	0000eebdbf8b402200af641e23390d4e5add9bee0bb1e0effd75a320f101b490
d.prabakaran;A718I	00002fc1f07161334d87334339ec25620314000081b14951e06d0fa915d49bec
```

### Coins Found when Tested with Vignesh Raj (`vigneshr.tirupat`):
```text
vigneshr.tirupat;DAFR9	0000a2c0846486a78fa69cbe077a6eb150e9477cd605d976140e1b3c964d1a1c
vigneshr.tirupat;CD25Z	00008b0a456b65305e798e5931d3e0270937dac1ac4200fe8c6836260f6a19ca
vigneshr.tirupat;D0CUL	00004caadc58f47a23f5b0bb343aabdab469dbf7d873ec16de2c029e19594e2a
vigneshr.tirupat;C0VY7	0000f89c05e8682c1bc5f60dff6e36a8eb40ecd5d58a0184462b77d2380a8d6f
vigneshr.tirupat;D6F83	00008e8166f6338567c1d2c65843518e86811f02682814ae24a434715e8811e1
vigneshr.tirupat;D0EZX	0000ba4aad9c482f50e4dd8403cb0f9c8b5119e550fb73bd88277c0ec1d9fa54
vigneshr.tirupat;9WXSN	000044d2c4bf223a01f600644bc86e875911b644e74020ad1fb85e1c7de2153d
vigneshr.tirupat;9YYRZ	000007575e3ee58e1857e4553ce869830258d4b3a75bc13f1dd3f8b73b8390e8
```

*(Output strictly matches the required `<InputString>\t<SHA-256>` format).*
---

## 4. Screenshots - Boss Terminal

**Boss Terminal (Server – `192.168.0.13`, Linux Ubuntu):**

<img width="678" height="292" alt="boss" src="https://github.com/user-attachments/assets/bc8dbbf8-73f0-42fc-affa-1d2f84bc05a2" />

**Worker Terminal (Remote Machine, Mac):**

<img width="1106" height="188" alt="worker" src="https://github.com/user-attachments/assets/19808caf-3df1-4864-a05a-ba34ccffa390" />

---

## 5. Running Time & CPU-to-Real-Time Ratio


We measured execution time using the system `time` command while mining for $K = 4$ for approximately 60 seconds on a 16-core machine:

- **Real Time (Elapsed):** `60.11 s`
- **CPU Time (User + System):** `934.71 s`
- **Ratio (CPU Time / Real Time):** **`15.55`**

### Explanation:
The ratio of **15.55** on a 16-core CPU shows that all 16 cores were computing in parallel simultaneously ($15.55 / 16 \approx 97.2\%$ core utilization). A ratio close to 1.0 would mean sequential execution. Our ratio of 15.55 confirms near-linear parallel speedup achieved by Erlang's actor model.

---

## 6. Coin with the Most Zeros Found

During extended mining runs, we found coins with 5 and 6 leading zeros:

- **Danush Prabhakaran (`d.prabakaran`) [Default in Code]:**
  - **Input String:** `d.prabakaran;LUS4J`
  - **SHA-256 Hash:** `000000164c8c1f2074984ef934554dd7366061d01b3d31553bb0417875b5ab46` (6 leading zeros)

- **Vignesh Raj Tirupattur Subramaniam Ravichandran (`vigneshr.tirupat`) [Tested]:**
  - **Input String:** `vigneshr.tirupat;9YYRZ`
  - **SHA-256 Hash:** `000007575e3ee58e1857e4553ce869830258d4b3a75bc13f1dd3f8b73b8390e8` (5 leading zeros)

---

## 7. Largest Number of Working Machines / Laptops Run On

We tested our distributed miner across **2 physical machines / laptops** (1 server + 1 remote worker node) over a local Wi-Fi network:

| Machine | Role | OS | Cores | IP Address |
| :--- | :--- | :--- | :--- | :--- |
| **Machine 1** | Server (Boss + Local Workers) | Linux (Ubuntu) | 16 Cores | `192.168.0.13` |
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

## 8. How to Run


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
.\myprogram.bat 192.168.0.26

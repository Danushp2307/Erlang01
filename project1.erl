%%%-------------------------------------------------------------------
%%% @doc
%%% COP5615 Distributed Operating System Principles - Project 1
%%% Distributed Bitcoin Miner using Erlang and the Actor Model.
%%%
%%% Features:
%%% - Boss Actor: coordinates non-overlapping work chunk distribution,
%%%   handles dynamic worker registration (local and remote), prints coins.
%%% - Worker Actors: local and remote workers request work, perform
%%%   high-performance binary SHA-256 prefix checks, and report coins.
%%% - Distributed Erlang: seamless remote clustering with location transparency.
%%% - Core Utilization & Wall-Clock statistics reporting.
%%% @end
%%%-------------------------------------------------------------------
-module(project1).
-export([main/1, start_server/1, start_worker/1, boss_init/2, worker_init/2]).

%% Default configuration constants
-define(DEFAULT_GATOR_ID, "danush").
-define(COOKIE, 'cop5615_cookie').
-define(DEFAULT_CHUNK_SIZE, 100000). %% 100k hashes per work unit

%%--------------------------------------------------------------------
%% Entry point for escript or CLI execution
%%--------------------------------------------------------------------
main([]) ->
    io:format("Usage:~n"),
    io:format("  Server mode: escript project1.escript <LeadingZeros>~n"),
    io:format("  Worker mode: escript project1.escript <ServerIP>~n"),
    halt(1);
main([Arg | _]) ->
    ArgStr = if is_atom(Arg) -> atom_to_list(Arg);
                is_list(Arg) -> Arg;
                is_binary(Arg) -> binary_to_list(Arg)
             end,
    case string:to_integer(ArgStr) of
        {K, []} when is_integer(K), K >= 0 ->
            start_server(K);
        _ ->
            start_worker(ArgStr)
    end.

%%--------------------------------------------------------------------
%% Server Mode
%%--------------------------------------------------------------------
start_server(K) ->
    %% Start distributed node if not already alive
    LocalIP = get_local_ip(),
    init_distributed_node(server, LocalIP),

    io:format("================================================================~n"),
    io:format("  Distributed Bitcoin Miner (COP5615 Project 1) - SERVER MODE~n"),
    io:format("================================================================~n"),
    io:format("Target Leading Zeros (K) : ~p~n", [K]),
    io:format("GatorLink ID Prefix      : ~s~n", [?DEFAULT_GATOR_ID]),
    io:format("Work Unit Size           : ~p hashes/request~n", [?DEFAULT_CHUNK_SIZE]),
    io:format("Server Node Name         : ~p~n", [node()]),
    io:format("Local IP for Workers     : ~s~n", [LocalIP]),
    NumCores = erlang:system_info(schedulers_online),
    io:format("Local Cores Detected     : ~p~n", [NumCores]),
    io:format("----------------------------------------------------------------~n"),
    io:format("Input String\t\t\t\t\t\tSHA-256 Hash~n"),
    io:format("----------------------------------------------------------------~n"),

    %% Spawn and register the Boss actor
    BossPid = spawn(?MODULE, boss_init, [K, ?DEFAULT_CHUNK_SIZE]),
    register(boss, BossPid),

    %% Spawn local worker actors (1-2 per core for optimal saturation)
    WorkerCount = NumCores * 2,
    spawn_workers(BossPid, WorkerCount),

    %% Start stats reporter process to display performance metrics periodically
    spawn(fun() -> stats_loop(BossPid) end),

    %% Keep server alive
    wait_forever().

%%--------------------------------------------------------------------
%% Worker Mode (Runs on remote machines)
%%--------------------------------------------------------------------
start_worker(ServerHostOrIP) ->
    %% Worker node initialization
    LocalIP = get_local_ip(),
    WorkerId = integer_to_list(erlang:unique_integer([positive])),
    WorkerNodeName = list_to_atom("worker_" ++ WorkerId ++ "@" ++ LocalIP),
    init_node_custom(WorkerNodeName),

    ServerNode = case string:find(ServerHostOrIP, "@") of
        nomatch -> list_to_atom("server@" ++ ServerHostOrIP);
        _ -> list_to_atom(ServerHostOrIP)
    end,
    connect_to_server(ServerNode, 10),

    NumCores = erlang:system_info(schedulers_online),
    WorkerCount = NumCores * 2,

    %% Spawn local workers on the remote machine that request work from remote Boss
    BossRef = {boss, ServerNode},
    spawn_workers(BossRef, WorkerCount),

    %% Remote worker displays nothing to stdout as per specification
    wait_forever().

%%--------------------------------------------------------------------
%% Boss Actor Logic
%%--------------------------------------------------------------------
boss_init(K, ChunkSize) ->
    net_kernel:monitor_nodes(true),
    statistics(runtime),
    statistics(wall_clock),
    boss_loop(0, K, ChunkSize, 0, []).

boss_loop(NextIndex, K, ChunkSize, TotalCoins, ConnectedNodes) ->
    receive
        {nodeup, Node} ->
            io:format("~n>>> [CLUSTER EVENT] Remote worker node connected: ~p~n~n", [Node]),
            NewNodes = [Node | lists:delete(Node, ConnectedNodes)],
            boss_loop(NextIndex, K, ChunkSize, TotalCoins, NewNodes);

        {nodedown, Node} ->
            io:format("~n>>> [CLUSTER EVENT] Worker node disconnected: ~p~n~n", [Node]),
            NewNodes = lists:delete(Node, ConnectedNodes),
            boss_loop(NextIndex, K, ChunkSize, TotalCoins, NewNodes);

        {get_work, WorkerPid} ->
            StartIndex = NextIndex,
            EndIndex = NextIndex + ChunkSize - 1,
            WorkerPid ! {work, StartIndex, EndIndex, K, ?DEFAULT_GATOR_ID},
            boss_loop(NextIndex + ChunkSize, K, ChunkSize, TotalCoins, ConnectedNodes);

        {coin_found, InputStr, HashHex} ->
            %% Print strictly in the required format: <input string>\t<hash>
            io:format("~s\t~s~n", [InputStr, HashHex]),
            boss_loop(NextIndex, K, ChunkSize, TotalCoins + 1, ConnectedNodes);

        {get_stats, ReplyTo} ->
            {_, CpuTime} = statistics(runtime),
            {_, RealTime} = statistics(wall_clock),
            ReplyTo ! {stats_reply, CpuTime, RealTime, TotalCoins, NextIndex, ConnectedNodes},
            boss_loop(NextIndex, K, ChunkSize, TotalCoins, ConnectedNodes);

        _Other ->
            boss_loop(NextIndex, K, ChunkSize, TotalCoins, ConnectedNodes)
    end.

%%--------------------------------------------------------------------
%% Worker Actor Logic
%%--------------------------------------------------------------------
spawn_workers(_Boss, 0) -> ok;
spawn_workers(Boss, Count) ->
    spawn(?MODULE, worker_init, [Boss, self()]),
    spawn_workers(Boss, Count - 1).

worker_init(Boss, _Parent) ->
    worker_loop(Boss).

worker_loop(Boss) ->
    %% Request work unit from Boss
    Boss ! {get_work, self()},
    receive
        {work, StartIndex, EndIndex, K, GatorId} ->
            mine_range(Boss, StartIndex, EndIndex, K, GatorId),
            worker_loop(Boss);
        stop ->
            ok
    after 10000 ->
        %% Timeout fallback: retry work request if Boss was temporarily busy
        worker_loop(Boss)
    end.

%% Mine an assigned index range
mine_range(_Boss, Current, End, _K, _GatorId) when Current > End ->
    ok;
mine_range(Boss, Current, End, K, GatorId) ->
    %% Candidate string format: GatorID;Index (e.g. danush;10042)
    Candidate = GatorId ++ ";" ++ integer_to_list(Current, 36),
    HashBinary = crypto:hash(sha256, Candidate),
    case has_leading_zeros(HashBinary, K) of
        true ->
            HashHex = binary_to_hex(HashBinary),
            Boss ! {coin_found, Candidate, HashHex};
        false ->
            ok
    end,
    mine_range(Boss, Current + 1, End, K, GatorId).

%%--------------------------------------------------------------------
%% Optimized Binary Leading Zeros Check
%% Validates K hex zeros directly on raw binary before hex formatting
%%--------------------------------------------------------------------
has_leading_zeros(_, 0) -> true;
has_leading_zeros(<<0:8, Rest/binary>>, K) when K >= 2 ->
    has_leading_zeros(Rest, K - 2);
has_leading_zeros(<<Byte:8, _/binary>>, 1) ->
    Byte < 16;
has_leading_zeros(_, _) ->
    false.

%% Converts 32-byte binary hash to lowercase hex string
binary_to_hex(Binary) ->
    [nibble_to_hex(N) || <<N:4>> <= Binary].

nibble_to_hex(N) when N < 10 -> $0 + N;
nibble_to_hex(N) -> $a + (N - 10).

%%--------------------------------------------------------------------
%% Node Initialization & Distributed Networking
%%--------------------------------------------------------------------
init_distributed_node(Role, LocalIP) ->
    case node() of
        'nonode@nohost' ->
            NodeName = list_to_atom(atom_to_list(Role) ++ "@" ++ LocalIP),
            init_node_custom(NodeName);
        _ExistingNode ->
            erlang:set_cookie(node(), ?COOKIE),
            ok
    end.

init_node_custom(NodeName) ->
    case net_kernel:start([NodeName, longnames]) of
        {ok, _} ->
            erlang:set_cookie(node(), ?COOKIE),
            ok;
        {error, _Reason} ->
            %% Try shortnames if longnames failed (e.g. without FQDN)
            case net_kernel:start([NodeName, shortnames]) of
                {ok, _} ->
                    erlang:set_cookie(node(), ?COOKIE),
                    ok;
                {error, Reason2} ->
                    %% Standalone local node fallback
                    io:format("[Notice] Operating in local standalone mode: ~p~n", [Reason2]),
                    ok
            end
    end.

connect_to_server(_ServerNode, 0) ->
    io:format("Error: Could not connect to server after multiple attempts.~n"),
    halt(1);
connect_to_server(ServerNode, AttemptsLeft) ->
    case net_adm:ping(ServerNode) of
        pong ->
            ok;
        pang ->
            timer:sleep(1000),
            connect_to_server(ServerNode, AttemptsLeft - 1)
    end.

%% Discovers local routable IPv4 address
get_local_ip() ->
    case inet:getifaddrs() of
        {ok, IfList} ->
            case find_valid_ipv4(IfList) of
                {ok, IP} -> IP;
                _ -> "127.0.0.1"
            end;
        _ ->
            "127.0.0.1"
    end.

find_valid_ipv4([]) ->
    error;
find_valid_ipv4([{_IfName, Opts} | Rest]) ->
    Flags = proplists:get_value(flags, Opts, []),
    IsUp = lists:member(up, Flags),
    IsLoopback = lists:member(loopback, Flags),
    case IsUp andalso not IsLoopback of
        true ->
            Addrs = [Addr || {addr, Addr} <- Opts, is_tuple(Addr), tuple_size(Addr) == 4],
            case filter_routable_ip(Addrs) of
                {ok, IPStr} -> {ok, IPStr};
                error -> find_valid_ipv4(Rest)
            end;
        false ->
            find_valid_ipv4(Rest)
    end.

filter_routable_ip([]) -> error;
filter_routable_ip([{127, _, _, _} | Rest]) -> filter_routable_ip(Rest);
filter_routable_ip([{169, 254, _, _} | Rest]) -> filter_routable_ip(Rest);
filter_routable_ip([{A, B, C, D} | _]) ->
    {ok, lists:flatten(io_lib:format("~p.~p.~p.~p", [A, B, C, D]))}.

%% Periodically displays CPU time, Real time, and Core Utilization Ratio
stats_loop(BossPid) ->
    timer:sleep(15000), %% Print stats every 15 seconds
    BossPid ! {get_stats, self()},
    receive
        {stats_reply, CpuTime, RealTime, CoinsFound, HashesEvaluated, ConnectedNodes} ->
            Ratio = if RealTime > 0 -> CpuTime / RealTime; true -> 0.0 end,
            io:format("~n>>> [STATS] CPU Time: ~p ms | Real Time: ~p ms | Ratio (CPU/Real): ~.2f | Total Coins: ~p | Hashes Checked: ~p | Connected Nodes: ~p~n~n",
                      [CpuTime, RealTime, Ratio, CoinsFound, HashesEvaluated, ConnectedNodes]);
        _ ->
            ok
    end,
    stats_loop(BossPid).

wait_forever() ->
    receive
        _ -> wait_forever()
    end.


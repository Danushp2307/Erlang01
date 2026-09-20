#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable

%%%-------------------------------------------------------------------
%%% COP5615 Project 1: Distributed Bitcoin Miner Escript
%%% Usage:
%%%   escript project1.escript <k>            (Server Mode)
%%%   escript project1.escript <server_ip>    (Worker Mode)
%%%-------------------------------------------------------------------

-define(DEFAULT_GATOR_ID, "danush").
-define(COOKIE, 'cop5615_cookie').
-define(DEFAULT_CHUNK_SIZE, 100000).

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

    io:format("Server started.~n"), 
    io:format("K = ~p~n", [K]),
    io:format("Server node = ~p~n", [node()]),
    io:format("Server IP = ~s~n", [LocalIP]),
    NumCores = erlang:system_info(schedulers_online),

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
    LocalIP = get_local_ip(),
    WorkerId = integer_to_list(erlang:unique_integer([positive])),
    WorkerNode = list_to_atom("worker_" ++ WorkerId ++ "@" ++ LocalIP),

    init_node_custom(WorkerNode),
    ServerNode =
        case string:find(ServerHostOrIP, "@") of
            nomatch ->
                list_to_atom("server@" ++ ServerHostOrIP);
            _ ->
                list_to_atom(ServerHostOrIP)
        end,

    connect_to_server(ServerNode, 10),

    NumCores = erlang:system_info(schedulers_online),
    WorkerCount = NumCores * 2,

    Boss = {boss, ServerNode},
    spawn_workers(Boss, WorkerCount),

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
            io:format("Worker connected: ~p~n", [Node]),
            Nodes = [Node | lists:delete(Node, ConnectedNodes)],
            boss_loop(NextIndex, K, ChunkSize, TotalCoins, Nodes);

        {nodedown, Node} ->
            io:format("Worker disconnected: ~p~n", [Node]),
            Nodes = lists:delete(Node, ConnectedNodes),
            boss_loop(NextIndex, K, ChunkSize, TotalCoins, Nodes);

        {get_work, WorkerPid} ->
            Start = NextIndex,
            End = Start + ChunkSize - 1,
            WorkerPid ! {work, Start, End, K, ?DEFAULT_GATOR_ID},
            boss_loop(NextIndex + ChunkSize, K, ChunkSize,
                      TotalCoins, ConnectedNodes);

        {coin_found, InputStr, HashHex} ->
            io:format("~s\t~s~n", [InputStr, HashHex]),
            boss_loop(NextIndex, K, ChunkSize,
                      TotalCoins + 1, ConnectedNodes);

        {get_stats, ReplyTo} ->
            {_, CpuTime} = statistics(runtime),
            {_, RealTime} = statistics(wall_clock),
            ReplyTo ! {stats_reply, CpuTime, RealTime,
                       TotalCoins, NextIndex, ConnectedNodes},
            boss_loop(NextIndex, K, ChunkSize,
                      TotalCoins, ConnectedNodes);

        _ ->
            boss_loop(NextIndex, K, ChunkSize,
                      TotalCoins, ConnectedNodes)
    end.

%%--------------------------------------------------------------------
%% Worker Actor Logic
%%--------------------------------------------------------------------
spawn_workers(_Boss, 0) -> ok;
spawn_workers(Boss, Number) ->
    spawn(?MODULE, worker_init, [Boss]),
    spawn_workers(Boss, Number - 1).

worker_init(Boss) ->
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

mine_range(Boss,Current, End, K, GatorId) ->
    Candidate = GatorId ++ ";" ++ integer_to_list(Current, 36),
    Hash = crypto:hash(sha256, Candidate),

    case has_leading_zeros(Hash, K) of
        true ->
            HashHex = binary_to_hex(Hash),
            Boss ! {coin_found, Candidate, HashHex};
        false ->
            ok
    end,

    mine_range(Boss,Current + 1, End, K, GatorId).

%%--------------------------------------------------------------------
%% Optimized Binary Leading Zeros Check
%% Validates K hex zeros directly on raw binary before hex formatting
%%--------------------------------------------------------------------
has_leading_zeros(Hash, K) ->
    HashHex = binary_to_hex(Hash),
    Prefix = lists:duplicate(K, $0),
    lists:prefix(Prefix, HashHex).

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
                {error, Reason} ->
                    %% Standalone local node fallback
                    io:format("[Notice] Operating in local standalone mode: ~p~n", [Reason]),
                    ok
            end
    end.

connect_to_server(_, 0) ->
    io:format("Could not connect to server.~n"),
    halt(1);

connect_to_server(ServerNode, Attempts) ->
    case net_adm:ping(ServerNode) of
        pong ->
            ok;
        pang ->
            timer:sleep(1000),
            connect_to_server(ServerNode, Attempts - 1)
    end.

%% Discovers local routable IPv4 address
get_local_ip() ->
    case inet:getifaddrs() of
        {ok, IfList} ->
            case find_valid_ipv4(IfList) of
                {ok, IP} -> IP;
                error -> "127.0.0.1"
            end;
        _ ->
            "127.0.0.1"
    end.
find_valid_ipv4([]) ->
    error;

find_valid_ipv4([{_Name, Opts} | Rest]) ->
    Flags = proplists:get_value(flags, Opts, []),

    case lists:member(up, Flags) andalso
         not lists:member(loopback, Flags) of
        true ->
            Addrs = [IP || {addr, IP} <- Opts,
                           is_tuple(IP),
                           tuple_size(IP) == 4],

            case filter_routable_ip(Addrs) of
                {ok, IP} -> {ok, IP};
                error -> find_valid_ipv4(Rest)
            end;

        false ->
            find_valid_ipv4(Rest)
    end.

filter_routable_ip([]) ->
    error;

filter_routable_ip([IP | Rest]) ->
    case IP of
        {127, _, _, _} ->
            filter_routable_ip(Rest);

        {169, 254, _, _} ->
            filter_routable_ip(Rest);

        {A, B, C, D} ->
            Address = io_lib:format("~p.~p.~p.~p", [A, B, C, D]),
            {ok, lists:flatten(Address)}
    end.

%% Periodically displays CPU time, Real time, and Core Utilization Ratio
stats_loop(BossPid) ->
    timer:sleep(15000),
    BossPid ! {get_stats, self()},

    receive
        {stats_reply, CpuTime, RealTime, CoinsFound, HashesEvaluated, ConnectedNodes} ->
            Ratio =
                case RealTime > 0 of
                    true -> CpuTime / RealTime;
                    false -> 0.0
                end,

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

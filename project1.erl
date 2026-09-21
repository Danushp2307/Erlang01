%% COP5615 Project 1 - Distributed Bitcoin Miner (Danush & Vignesh Raj)
-module(project1).
-export([main/1, start_server/1, start_worker/1, boss_loop/3, worker_loop/1]).

-define(GATOR_ID, "danush").
-define(WORK_UNIT_SIZE, 100000). %% 100k hashes per request
-define(COOKIE, 'cop5615_cookie').

%% CLI entry point
main([]) ->
    io:format("Usage:~n"),
    io:format("  Server mode: ./myprogram <LeadingZeros>~n"),
    io:format("  Worker mode: ./myprogram <ServerIP>~n"),
    halt(1);
main([Arg | _]) ->
    start_from_argument(Arg).

start_from_argument(Arg) ->
    ArgStr = if is_atom(Arg) -> atom_to_list(Arg); is_list(Arg) -> Arg end,
    case string:to_integer(ArgStr) of
        {K, []} when K >= 0 -> start_server(K);
        _                   -> start_worker(ArgStr)
    end.

%% Server mode: starts Boss actor and local workers
start_server(LeadingZeros) ->
    ensure_node(server),
    BossPid = spawn(fun() ->
        net_kernel:monitor_nodes(true),
        boss_loop(0, LeadingZeros, ?WORK_UNIT_SIZE)
    end),
    register(boss, BossPid),
    Cores = erlang:system_info(schedulers_online),
    spawn_workers(BossPid, Cores * 2),
    keep_alive().

%% Worker mode: connects to server and mines remotely
start_worker(ServerIP) ->
    ensure_node(worker),
    ServerNode = case string:find(ServerIP, "@") of
        nomatch -> list_to_atom("server@" ++ ServerIP);
        _       -> list_to_atom(ServerIP)
    end,
    connect_server(ServerNode, 10),
    io:format("Worker joined the boss server (~p) and received work.~n", [ServerNode]),
    Boss = {boss, ServerNode},
    Cores = erlang:system_info(schedulers_online),
    spawn_workers(Boss, Cores * 2),
    keep_alive().

%% Start distributed node if not already started
ensure_node(Role) ->
    case node() of
        'nonode@nohost' ->
            Name = case Role of
                server -> server;
                worker -> list_to_atom("worker_" ++ integer_to_list(erlang:unique_integer([positive])))
            end,
            case net_kernel:start([Name, shortnames]) of
                {ok, _} -> erlang:set_cookie(node(), ?COOKIE);
                _       -> ok
            end;
        _ ->
            erlang:set_cookie(node(), ?COOKIE)
    end.

%% Ping server with retry
connect_server(_, 0) -> halt(1);
connect_server(Node, Attempts) ->
    case net_adm:ping(Node) of
        pong -> ok;
        pang -> timer:sleep(500), connect_server(Node, Attempts - 1)
    end.

%% Boss actor: assigns non-overlapping ranges and prints coins
boss_loop(NextIndex, LeadingZeros, ChunkSize) ->
    receive
        {nodeup, Node} ->
            io:format("Worker has joined the boss server: ~p~n", [Node]),
            boss_loop(NextIndex, LeadingZeros, ChunkSize);

        {nodedown, Node} ->
            io:format("Worker disconnected: ~p~n", [Node]),
            boss_loop(NextIndex, LeadingZeros, ChunkSize);

        {get_work, WorkerPid} ->
            StartIndex = NextIndex,
            EndIndex = NextIndex + ChunkSize - 1,
            WorkerPid ! {work, StartIndex, EndIndex, LeadingZeros},
            boss_loop(NextIndex + ChunkSize, LeadingZeros, ChunkSize);

        {coin_found, Candidate, HashHex} ->
            io:format("~s\t~s~n", [Candidate, HashHex]),
            boss_loop(NextIndex, LeadingZeros, ChunkSize)
    end.

%% Worker actor: pulls work and mines range
spawn_workers(_Boss, 0) -> ok;
spawn_workers(Boss, Count) ->
    spawn(?MODULE, worker_loop, [Boss]),
    spawn_workers(Boss, Count - 1).

worker_loop(Boss) ->
    Boss ! {get_work, self()},
    receive
        {work, StartIndex, EndIndex, LeadingZeros} ->
            mine_range(Boss, StartIndex, EndIndex, LeadingZeros),
            worker_loop(Boss);
        stop -> ok
    after 10000 ->
        worker_loop(Boss)
    end.

%% Mine assigned range
mine_range(_Boss, Current, End, _LeadingZeros) when Current > End -> ok;
mine_range(Boss, Current, End, LeadingZeros) ->
    Candidate = ?GATOR_ID ++ ";" ++ integer_to_list(Current, 36),
    Hash = crypto:hash(sha256, Candidate),
    case has_leading_zeros(Hash, LeadingZeros) of
        true ->
            HashHex = binary_to_hex(Hash),
            Boss ! {coin_found, Candidate, HashHex};
        false ->
            ok
    end,
    mine_range(Boss, Current + 1, End, LeadingZeros).

%% Check for K leading zeros in hash
has_leading_zeros(Hash, K) ->
    HashHex = binary_to_hex(Hash),
    Prefix = lists:duplicate(K, $0),
    lists:prefix(Prefix, HashHex).

%% Convert binary hash to lowercase hex string
binary_to_hex(Binary) ->
    [nibble_to_hex(N) || <<N:4>> <= Binary].

nibble_to_hex(N) when N < 10 -> $0 + N;
nibble_to_hex(N)             -> $a + N - 10.

keep_alive() ->
    receive _ -> keep_alive() end.

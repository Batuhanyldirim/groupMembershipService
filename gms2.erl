-module(gms2).
-export([start/1, start/2, mcast/2, stop/1]).

start(Id) ->
    Rnd = random:uniform(1000),
    Pid = spawn_link(fun() -> init(Id, Rnd, self()) end),
    io:format("~p: Master Node Created: ~p~n", [Id, Pid]),
    {ok, Pid}.

start(Id, Grp) ->
    Rnd = random:uniform(1000),
    Pid = spawn_link(fun() -> init(Id, Rnd, Grp, self()) end),
    io:format("~p: Slave Node Created: ~p~n", [Id, Pid]),
    {ok, Pid}.

init(Id, Rnd, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, [], [Master]).

init(Id, Rnd, Grp, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    Grp ! {join, Master, self()},
    receive
        {view, [Leader | Slaves], Group} ->
            io:format("~p: Joined group with leader ~p~n", [Id, Leader]),
            Master ! {view, Group},
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, Slaves, Group)
    after 5000 ->
        io:format("~p: No reply from leader, aborting join~n", [Id]),
        Master ! {error, "no reply from leader"},
        exit(timeout)
    end.

mcast(Pid, Msg) ->
    Pid ! {mcast, Msg}.

stop(Pid) ->
    Pid ! stop.

leader(Id, Master, Slaves, Group) ->
    receive
        {mcast, Msg} ->
            io:format("~p: Leader Received Multicast: ~p~n", [Id, Msg]),
            bcast(Id, {msg, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, Slaves, Group);
        {join, Wrk, Peer} ->
            Slaves2 = Slaves ++ [Peer],
            Group2 = Group ++ [Wrk],
            bcast(Id, {view, [self() | Slaves2], Group2}, Slaves2),
            Master ! {view, Group2},
            io:format("~p: Slave added: ~p~n", [Id, Slaves2]),
            leader(Id, Master, Slaves2, Group2);
        stop ->
            ok
    end.

slave(Id, Master, Leader, Slaves, Group) ->
    erlang:monitor(process, Leader),
    receive
        {mcast, Msg} ->
            io:format("~p: Slave Received Multicast from Master: ~p~n", [Id, Msg]),
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group);
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group);
        {msg, Msg} ->
            io:format("~p: Slave received message from leader: ~p~n", [Id, Msg]),
            Master ! Msg,
            slave(Id, Master, Leader, Slaves, Group);
        {view, [NewLeader | NewSlaves], NewGroup} ->
            io:format("~p: Slave received new view: ~p~n", [Id, NewGroup]),
            Master ! {view, NewGroup},
            slave(Id, Master, NewLeader, NewSlaves, NewGroup);
        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("~p: Leader crashed, starting election~n", [Id]),
            election(Id, Master, Slaves, Group);
        stop ->
            ok
    end.

election(Id, Master, Slaves, Group) ->
    Self = self(),
    case Slaves of
        [Self | Rest] ->
            io:format("~p: Elected as the new leader~n", [Id]),
            bcast(Id, {view, [Self | Rest], Group}, Rest),
            Master ! {view, Group},
            leader(Id, Master, Rest, Group);
        [NewLeader | Rest] ->
            io:format("~p: New leader elected: ~p~n", [Id, NewLeader]),
            erlang:monitor(process, NewLeader),
            slave(Id, Master, NewLeader, Rest, Group)
    end.

bcast(Id, Msg, Nodes) ->
    lists:foreach(
        fun(Node) ->
            Node ! Msg,
            crash(Id)
        end,
        Nodes
    ).

crash(Id) ->
    case random:uniform(100) of
        100 ->
            io:format("~p: Crashing due to bad luck~n", [Id]),
            exit(no_luck);
        _ ->
            ok
    end.

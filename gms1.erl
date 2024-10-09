-module(gms1).
-export([start/1, start/2, mcast/2, stop/1]).

start(Id) ->
    Master = self(),
    io:format("~p: Master Node Created: ~p~n", [Id, Master]),
    Pid = spawn_link(fun() -> init(Id, Master) end),
    {ok, Pid}.

start(Id, Grp) ->
    Master = self(),
    io:format("~p: Slave Node Created: ~p~n", [Id, Master]),
    Pid = spawn_link(fun() -> init(Id, Grp, Master) end),
    {ok, Pid}.

init(Id, Master) ->
    leader(Id, Master, [], [Master]).

init(Id, Grp, Master) ->
    Grp ! {join, Master, self()},
    receive
        {view, [Leader | Slaves], Group} ->
            io:format("~p: Joined group with leader ~p~n", [Id, Leader]),
            Master ! {view, Group},
            slave(Id, Master, Leader, Slaves, Group)
    after 5000 ->
        io:format("~p: Failed to join the group~n", [Id]),
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
    receive
        {mcast, Msg} ->
            io:format("~p: Slave Received Multicast from Master: ~p~n", [Id, Msg]),
            % Forward to leader
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group);
        {join, Wrk, Peer} ->
            % Forward join request to leader
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group);
        {msg, Msg} ->
            io:format("~p: Slave received message from leader: ~p~n", [Id, Msg]),
            % Deliver to application layer
            Master ! Msg,
            slave(Id, Master, Leader, Slaves, Group);
        {view, [NewLeader | NewSlaves], NewGroup} ->
            io:format("~p: Slave received new view: ~p~n", [Id, NewGroup]),
            Master ! {view, NewGroup},
            slave(Id, Master, NewLeader, NewSlaves, NewGroup);
        stop ->
            ok
    end.

bcast(Id, Msg, Peers) ->
    % io:format("~p: Broadcasting message ~p to peers: ~p~n", [Id, Msg, Peers]),
    lists:foreach(
        fun(Peer) ->
            Peer ! Msg
        end,
        Peers
    ).

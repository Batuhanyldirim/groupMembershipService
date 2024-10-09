-module(worker).
-export([start/1, start/2, mcast/2, stop/1]).

start(Id) ->
    {ok, GrpPid} = gms3:start(Id),
    Pid = spawn_link(fun() -> worker_loop(Id, GrpPid) end),
    {Pid, GrpPid}.

start(Id, GrpPid) ->
    {ok, NewGrpPid} = gms3:start(Id, GrpPid),
    Pid = spawn_link(fun() -> worker_loop(Id, NewGrpPid) end),
    {Pid, NewGrpPid}.

worker_loop(Id, GrpPid) ->
    receive
        {view, Group} ->
            io:format("~p: Worker received new view: ~p~n", [Id, Group]),
            worker_loop(Id, GrpPid);
        Msg ->
            io:format("~p: Worker received message: ~p~n", [Id, Msg]),
            worker_loop(Id, GrpPid)
    end.

mcast(GrpPid, Msg) ->
    gms3:mcast(GrpPid, Msg).

stop(GrpPid) ->
    gms3:stop(GrpPid).

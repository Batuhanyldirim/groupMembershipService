-module(gms3).
-export([start/1, start/2, mcast/2, stop/1]).

start(Id) ->
    Rnd = random:uniform(1000),
    Pid = spawn_link(fun() -> init(Id, Rnd, "none", self()) end),
    io:format("~p: Master Node Created: ~p~n", [Id, Pid]),
    {ok, Pid}.

start(Id, Grp) ->
    Rnd = random:uniform(1000),
    Pid = spawn_link(fun() -> init(Id, Rnd, "none", Grp, self()) end),
    io:format("~p: Slave Node Created: ~p~n", [Id, Pid]),
    {ok, Pid}.

init(Id, Rnd, Color, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, 1, [], [Master], Color).

init(Id, Rnd, Color, Grp, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    Grp ! {join, Master, self()},
    receive
        {view, N, [Leader | Slaves], Group, LeaderColor} ->
            io:format("~p: Joined group with leader ~p, updating state to ~p~n", [
                Id, Leader, LeaderColor
            ]),
            Master ! {view, Group},
            Master ! {color_update, LeaderColor},
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N, none, Slaves, Group, LeaderColor)
    after 5000 ->
        io:format("~p: No reply from leader, aborting join~n", [Id]),
        Master ! {error, "no reply from leader"},
        exit(timeout)
    end.

mcast(Pid, Msg) ->
    Pid ! {mcast, Msg}.

stop(Pid) ->
    Pid ! stop.

leader(Id, Master, N, Slaves, Group, Color) ->
    receive
        {mcast, NewColor} ->
            io:format("~p: Leader Received Multicast: ~p (Seq: ~p)~n", [Id, NewColor, N]),
            io:format("~p: Updating leader state to color: ~p~n", [Id, NewColor]),
            NewState = NewColor,
            bcast(Id, {msg, N, NewColor}, Slaves),
            Master ! {msg, N, NewColor},
            SlavesWithoutSelf = lists:delete(self(), Slaves),
            wait_for_acks(Id, Master, N, NewColor, SlavesWithoutSelf, Group, NewState);
        {join, Wrk, Peer} ->
            Slaves2 = Slaves ++ [Peer],
            Group2 = Group ++ [Wrk],
            bcast(Id, {view, N, [self() | Slaves2], Group2, Color}, Slaves2),
            Master ! {view, N, Group2},
            io:format("~p: Slave added: ~p (Seq: ~p), sending state: ~p~n", [Id, Slaves2, N, Color]),
            leader(Id, Master, N + 1, Slaves2, Group2, Color);
        stop ->
            ok
    end.

wait_for_acks(Id, Master, N, Msg, Slaves, Group, Color) ->
    receive
        {ack, Slave, Seq} when Seq == N ->
            io:format("~p: Received ACK from ~p for Seq: ~p~n", [Id, Slave, Seq]),
            Slaves2 = lists:delete(Slave, Slaves),
            if
                Slaves2 == [] ->
                    io:format("~p: All ACKs received for Seq: ~p, resetting state~n", [Id, N]),
                    leader(Id, Master, N + 1, Group, Group, Color);
                true ->
                    wait_for_acks(Id, Master, N, Msg, Slaves2, Group, Color)
            end
    after 5000 ->
        io:format("~p: Timeout, resending message (Seq: ~p)~n", [Id, N]),
        bcast(Id, {msg, N, Msg}, Slaves),
        wait_for_acks(Id, Master, N, Msg, Slaves, Group, Color)
    end.

%%% Slave Logic with ACKs and Waiting for Leader's Broadcast
slave(Id, Master, Leader, N, Last, Slaves, Group, Color) ->
    receive
        {mcast, NewColor} ->
            io:format("~p: Slave Received Multicast from Master: ~p (Seq: ~p)~n", [Id, NewColor, N]),
            % Forward to leader and wait for the leader's broadcast
            Leader ! {mcast, NewColor},
            wait_for_broadcast(Id, Master, Leader, N, Last, Slaves, Group, Color, NewColor);
        % Only process if sequence is greater or equal
        {msg, Seq, NewColor} when Seq >= N ->
            io:format(
                "~p: Slave received message from leader: ~p (Seq: ~p), updating state to ~p~n", [
                    Id, NewColor, Seq, NewColor
                ]
            ),
            % Update the color state
            NewState = NewColor,
            Master ! {color_update, NewState},
            % Send ACK back to the leader
            Leader ! {ack, self(), Seq},
            %% Update sequence and last message
            slave(Id, Master, Leader, Seq + 1, {msg, Seq, NewColor}, Slaves, Group, NewState);
        {view, Seq, [NewLeader | NewSlaves], NewGroup, LeaderColor} when Seq >= N ->
            io:format("~p: Slave received new view: ~p (Seq: ~p), updating state to ~p~n", [
                Id, NewGroup, Seq, LeaderColor
            ]),
            % Update the color state to the leader's state
            NewState = LeaderColor,
            Master ! {view, NewGroup},
            Master ! {color_update, NewState},
            % Send ACK back to the leader
            NewLeader ! {ack, self(), Seq},
            %% Update sequence and last view
            slave(
                Id, Master, NewLeader, Seq + 1, {view, Seq, NewGroup}, NewSlaves, NewGroup, NewState
            );
        % Dropping old messages
        {msg, Seq, _} when Seq < N ->
            io:format("~p: Old message with Seq: ~p received and dropped~n", [Id, Seq]),
            slave(Id, Master, Leader, N, Last, Slaves, Group, Color);
        {view, Seq, _, _} when Seq < N ->
            io:format("~p: Old view message with Seq: ~p received and dropped~n", [Id, Seq]),
            slave(Id, Master, Leader, N, Last, Slaves, Group, Color);
        % Leader has crashed
        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("~p: Leader crashed, starting election~n", [Id]),
            % Trigger election
            election(Id, Master, N, Last, Slaves, Group, Color);
        stop ->
            ok
    end.

%%% Wait for Broadcast from Leader (confirming delivery of the message)
wait_for_broadcast(Id, Master, Leader, N, Last, Slaves, Group, Color, SentColor) ->
    receive
        % The leader broadcasts the message to all slaves
        {msg, Seq, NewColor} when Seq == N, NewColor == SentColor ->
            io:format("~p: Slave confirmed message from leader: ~p (Seq: ~p)~n", [Id, NewColor, Seq]),
            % Update the color state to the sent color
            NewState = NewColor,
            Master ! {color_update, NewState},
            % Send ACK back to the leader
            Leader ! {ack, self(), Seq},
            %% Update sequence and last message
            slave(Id, Master, Leader, Seq + 1, {msg, Seq, NewColor}, Slaves, Group, NewState)
    after 5000 ->
        io:format("~p: Timeout waiting for broadcast from leader~n", [Id]),
        Leader ! {mcast, SentColor},
        wait_for_broadcast(Id, Master, Leader, N, Last, Slaves, Group, Color, SentColor)
    end.

election(Id, Master, N, Last, Slaves, Group, Color) ->
    Self = self(),
    case Slaves of
        [Self | Rest] ->
            io:format("~p: Elected as the new leader~n", [Id]),
            io:format("~p: Resending last message: ~p~n", [Id, Last]),
            bcast(Id, Last, Rest),
            leader(Id, Master, N, Rest, Group, Color);
        [NewLeader | Rest] ->
            io:format("~p: New leader elected: ~p~n", [Id, NewLeader]),
            % io:format("~p: Resending last message: ~p~n", [Id, Last]),
            % NewLeader ! {mcast, Last},
            erlang:monitor(process, NewLeader),
            slave(Id, Master, NewLeader, N, Last, Rest, Group, Color)
    end.

bcast(Id, Msg, Nodes) ->
    lists:foreach(
        fun(Node) ->
            Node ! Msg
        end,
        Nodes
    ).

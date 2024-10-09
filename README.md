# Groupy: A Group Membership Service

![Groupy Logo](./images/logo.png)

## Overview

This repository contains the implementation of **Groupy**, a group membership service that ensures reliable and consistent communication in a distributed system. Groupy implements a leader-based architecture where nodes broadcast state changes to each other while ensuring consistency even if the leader crashes. It handles leader election, reliable message delivery, and acknowledgment mechanisms for fault tolerance.

### Features:
- **Group Membership with Leader Election**: Nodes can join a group with an elected leader. If the leader fails, a new leader is elected automatically.
- **Atomic Multicast**: Ensures that all messages are reliably delivered to all working nodes in the correct order.
- **Failure Handling**: Detects node and leader failures, elects a new leader, and ensures consistency.
- **Reliable Multicasting**: Guarantees that even if the leader crashes, the new leader ensures that undelivered messages are properly handled using sequence numbers.
- **Acknowledgment Mechanism**: Messages are acknowledged by all nodes to confirm receipt.

## Table of Contents
- [Getting Started](#getting-started)
- [Usage](#usage)
  - [Creating Nodes](#creating-nodes)
  - [Sending Messages](#sending-messages)
  - [Leader Failure and Election](#leader-failure-and-election)
  - [Adding a New Node](#adding-a-new-node)
- [Evaluation](#evaluation)
- [Conclusion](#conclusion)

---

## Getting Started

### Prerequisites
- **Erlang/OTP** installed on your system.

To install Erlang, visit the [official Erlang website](https://www.erlang.org/downloads).

### Clone the Repository
```bash
git clone https://github.com/yourusername/groupy.git
cd groupy
```

### Compile the Modules
Ensure that you compile the Erlang files before testing:

```bash
erlc groupy.erl
```
## Usage
### Creating Nodes
The first step is to create nodes in the distributed system. The first node created will act as the leader and subsequent nodes will join as slaves.
```bash
1> {Pid1, GrpPid1} = worker:start(node1).
2> {Pid2, GrpPid2} = worker:start(node2, GrpPid1).
3> {Pid3, GrpPid3} = worker:start(node3, GrpPid1).
```
### Sending Messages
You can send messages to the group by multicasting them through the leader. All nodes will update their state based on the message received.
```bash
4> worker:mcast(GrpPid1, 'red').
5> worker:mcast(GrpPid1, 'blue').
```
### Leader Failure and Election
In the event of the leader failing, the system automatically elects a new leader and continues operations. Here's how to simulate a leader failure and ensure that a new leader is elected:
```bash
6> worker:stop(GrpPid1).  % Stop the leader
7> worker:mcast(GrpPid2, 'orange').  % Send a message from the new leader
```
### Adding a New Node
You can add new nodes to the system even after a leader failure. The new node will retrieve the current state of the system from the leader.
```bash
8> {Pid4, GrpPid4} = worker:start(node4, GrpPid2).
```
## Evaluation
To evaluate the system, a series of test cases were run where nodes were created, messages were multicast, and leader failures were simulated. The following scenarios were tested:

Node Creation and Multicast: Nodes were successfully created and messages were reliably delivered.
Leader Failure and Election: The system was able to detect a leader failure, elect a new leader, and continue operations without disruption.
Reliable Message Delivery: Sequence numbers ensured that nodes did not process duplicate messages.
Acknowledgment Handling: Acknowledgments were received from all slave nodes, and messages were resent if no acknowledgment was received.

## Conclusion
The implementation of Groupy demonstrates a reliable and fault-tolerant distributed system using a group membership service with leader election, reliable multicasting, and acknowledgment mechanisms. This project provided valuable insights into maintaining consistency in distributed systems, handling node failures, and ensuring reliable state updates across all nodes.

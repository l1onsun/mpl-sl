# Copyright (C) Matway Burkow
#
# This repository and all its contents belong to Matway Burkow (referred here and below as "the owner").
# The content is for demonstration purposes only.
# It is forbidden to use the content or any part of it for any purpose without explicit permission from the owner.
# By contributing to the repository, contributors acknowledge that ownership of their work transfers to the owner.

"Span.toSpan"      use
"String.String"    use
"String.printList" use
"String.toString"  use
"algorithm.="      use
"control.&&"       use
"control.Natx"     use
"control.Nat8"     use
"control.Int32"    use
# "control.ensure"   use
"control.failProc" use
"control.times"    use
"control.when"     use
"control.while"    use

"posix.EAGAIN"      use
"posix.EWOULDBLOCK" use
"posix.pipe"        use
"posix.write"       use
"socket.send"       use

"errno.errno" use

"sync/TcpConnection"     use
"sync/sync.canceled?"    use
"sync/sync.connectTcp"   use
"sync/sync.ipv4ToString" use
"sync/sync.listenTcp"    use
"sync/sync.spawn"        use
"sync/sync.yield"        use
"sync/sync.asyncRead"    use

syncTest: [];

getServerAndClientContexts: [
  address: port:;;

  serverContext: {address: address; port: port; CALL: [
    result:   String;
    acceptor: address port listenTcp !result;
    result "" = ~ [("listenTcp failed, " result LF) printList "" failProc] when

    connection: clientAddress: acceptor.accept !result;;
    result "" = ~ [("TcpAcceptor.accept failed, " result LF) printList "" failProc] when
    clientAddress address = ~ [("TcpAcceptor.accept returned unexpected address, " clientAddress ipv4ToString LF) printList "" failProc] when

    @connection
  ];} TcpConnection spawn;

  clientContext: {address: address; port: port; CALL: [
    result:     String;
    connection: address port connectTcp !result;
    result "" = ~ [("connectTcp failed, " result LF) printList "" failProc] when

    @connection
  ];} TcpConnection spawn;

  @serverContext @clientContext
];

repeatString: [
  string: count:; toString;
  repeatedString: String;

  count dynamic [
    string @repeatedString.cat
  ] times

  @repeatedString
];

fillUpSocketSendBuffer: [
  sockfd:;
  data: "a" 1000 repeatString;

  [0 data.size Natx cast data storageAddress sockfd send -1ix = ~] [] while

  lastErrorNumber: errno;
  lastErrorNumber EAGAIN = ~ [lastErrorNumber EWOULDBLOCK = ~] && [("send failed, result=" lastErrorNumber) printList "" failProc] when
];

writeSpan: [
  filedes: data: toSpan;;
  result: data.size Natx cast data.data storageAddress filedes write;
  result -1ix = [("writeSpan failed, result=" errno LF) printList "" failProc] when
  result
];

# Test that write does not block when read is canceled on the same fd
[
  _: client: 0x7F000001n32 6600n16 getServerAndClientContexts .get; .get;

  readContext: {connection: @client; CALL: [
    result: String;

    message: 1024 @connection.readString !result;
    result "canceled" = ~ [("TcpConnection.readString failed, " result LF) printList "" failProc] when
    message "" = ~ [("client received unexpected response, \"" message "\"\n") printList "" failProc] when
  ];} () spawn;

  writeContext: {connection: @client; CALL: [
    result: String;

    connection.connection fillUpSocketSendBuffer
    "Hello, World!" @connection.write !result
    result "" = ~ [("TcpConnection.write failed, " result LF) printList "" failProc] when
  ];} () spawn;

  yield
  @readContext.cancel
] call

# Test that read does not block when write is canceled on the same fd
[
  server: client: 0x7F000001n32 6600n16 getServerAndClientContexts .get; .get;

  readContext: {connection: @client; CALL: [
    result: String;

    message: 1024 @connection.readString !result;
    result "" = ~ [("TcpConnection.readString failed, " result LF) printList "" failProc] when
    message "Hello, World!" = ~ [("client received unexpected response, \"" message "\"\n") printList "" failProc] when
  ];} () spawn;

  writeContext: {connection: @client; CALL: [
    result: String;

    connection.connection fillUpSocketSendBuffer
    "Hello, World!" @connection.write !result
    result "canceled" = ~ [("TcpConnection.write failed, " result LF) printList "" failProc] when
  ];} () spawn;

  yield
  @writeContext.cancel

  result: "Hello, World!" @server.write;
  result "" = ~ [("TcpConnection.write failed, " result LF) printList "" failProc] when
] call

# Test that on cancel before resuming nothing is read from the socket buffer; fails on Windows
[
  server: client: 0x7F000001n32 6600n16 getServerAndClientContexts .get; .get;

  readContext: {connection: @client; CALL: [
    result: String;

    message: 1 @connection.readString !result;
    result "canceled" = ~ [("TcpConnection.readString failed, " result LF) printList "" failProc] when
    message "" = ~ [("client received unexpected response, \"" message "\"\n") printList "" failProc] when
  ];} () spawn;

  yield

  cancelContext: {context: @readContext; CALL: [
    @context.cancel
  ];} () spawn;

  result: "Hello, World!" @server.write;
  result "" = ~ [("TcpConnection.write failed, " result LF) printList "" failProc] when

  @cancelContext.wait
  @readContext  .wait

  message: 1024 @client.readString !result;
  result "" = ~ [("TcpConnection.readString failed, " result LF) printList "" failProc] when
  message "Hello, World!" = ~ [("client received unexpected response, \"" message "\"\n") printList "" failProc] when
] call


# Test asyncRead waits input non-blocking
[
  pipefd: {in: Int32; out: Int32;};
  @pipefd pipe 0 = ~ [("failed to create pipe, result=" errno LF) printList "" failProc] when
  readyToRead: FALSE;

  context: {
    readfd: pipefd.in;
    readyToRead: @readyToRead;
    CALL: [
      buffer: Nat8 10 array;
      TRUE @readyToRead set
      readCount: 10nx buffer storageAddress pipefd.in asyncRead;
      readCount 4ix = ~ [("expected readCount: " readCount LF) printList "" failProc] when
        ("readyToRead: " readyToRead LF) printList
      message: buffer toSpan.stringView;
      message "Hello" = ~ ["received unexpected message, \"" message "\"" LF] when
      FALSE @readyToRead set
    ];
  } () spawn;
  readyToRead FALSE = ~ [("expected not ready to read" LF) printList "" failProc] when
  yield
  readyToRead TRUE = ~ [("expected ready to read" LF) printList "" failProc] when
  writeCount: pipefd.out "Hello" writeSpan;
  writeCount 4ix = ~ [("unexpected write count " writeCount LF) printList "" failProc] when
  yield
  readyToRead FALSE = ~ [("expected not ready to read" LF) printList "" failProc] when
] call

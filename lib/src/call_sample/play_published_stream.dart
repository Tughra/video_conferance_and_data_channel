import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'dart:core';
import 'signaling.dart';

class PlayStream extends StatefulWidget {

  final String ip;
  final String type;
  final String id;

  PlayStream({Key? key, required this.ip, required this.type, required this.id})
      : super(key: key);

  @override
  _PlayStreamState createState() =>
      _PlayStreamState(serverIP: ip, serverType: type, streamId: id);
}

class _PlayStreamState extends State<PlayStream> {
  Signaling? _signaling;
  var _selfId;
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  final String serverIP;
  final String serverType;
  final String streamId;

  _PlayStreamState(
      {Key? key,
        required this.serverIP,
        required this.serverType,
        required this.streamId});

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling?.close();
    _remoteRenderer.dispose();
  }

  void _connect() async {
    print("Connect call to $serverIP");
    if (_signaling == null) {
      _signaling = Signaling(serverIP, serverType, streamId)..connect();
      _signaling?.callback=(String info,Map obj){};
      _signaling?.onStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.CallStateNew:
            this.setState(() {
              _inCalling = true;
            });
            break;
          case SignalingState.CallStateBye:
            this.setState(() {
              _remoteRenderer.srcObject = null;
              _inCalling = false;
             Get.back();
            });
            break;
          case SignalingState.CallStateInvite:
            this.setState(() {
              print("invitee");
            });
            break;
          case SignalingState.CallStateConnected:
          case SignalingState.CallStateRinging:
          case SignalingState.ConnectionClosed:
          case SignalingState.ConnectionError:
          case SignalingState.ConnectionOpen:
            break;
        }
      };

      _signaling?.onLocalStream = ((stream) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      });

      _signaling?.onAddRemoteStream = ((stream) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      });

      _signaling?.onRemoveRemoteStream = ((stream) {
        _remoteRenderer.srcObject = null;
      });
    }
  }

  _invitePeer(context, peerId, use_screen) async {
    if (_signaling != null && peerId != _selfId) {
      _signaling?.invite(peerId, 'video', use_screen);
    }
  }

  _hangUp() {
    if (_signaling != null) {
      _signaling?.bye();
    }
  }


  _buildRow(context, peer) {
    var self = (peer['id'] == _selfId);
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(self
            ? peer['name'] + '[Your self]'
            : peer['name'] + '[' + peer['user_agent'] + ']'),
        onTap: null,
        trailing: SizedBox(
            width: 100.0,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.videocam),
                    onPressed: () => _invitePeer(context, peer['id'], false),
                    tooltip: 'Video calling',
                  ),
                  IconButton(
                    icon: const Icon(Icons.screen_share),
                    onPressed: () => _invitePeer(context, peer['id'], true),
                    tooltip: 'Screen sharing',
                  )
                ])),
        subtitle: Text('id: ' + peer['id']),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Playing $streamId'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _inCalling
          ? SizedBox(
          width: 200.0,
          child: Row(
              mainAxisAlignment: serverType == 'publish'
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.center,
              children: <Widget>[
                FloatingActionButton(
                  heroTag: "1",
                  onPressed: _hangUp,
                  tooltip: 'Hangup',
                  child: Icon(Icons.call_end),
                  backgroundColor: Colors.pink,
                ),
              ]))
          : null,
      body: _inCalling
          ? OrientationBuilder(builder: (context, orientation) {
        return Container(
          child: Stack(children: <Widget>[
            Positioned(
                left: 0.0,
                right: 0.0,
                top: 0.0,
                bottom: 0.0,
                child: Container(
                  margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  child: RTCVideoView(_remoteRenderer),
                  decoration: BoxDecoration(color: Colors.black54),
                )),
            /*Positioned(
                    left: 20.0,
                    top: 20.0,
                    child: Container(    // useful when in a p2p call. small display for self video.
                      width: orientation == Orientation.portrait ? 90.0 : 120.0,
                      height:
                          orientation == Orientation.portrait ? 120.0 : 90.0,
                      child: RTCVideoView(_localRenderer),
                      decoration: BoxDecoration(color: Colors.black54),
                    ),
                  ),*/
          ]),
        );
      })
          : Stack(
        children: [
          Align(alignment: Alignment.topCenter,child: InkWell(onTap: (){
            print("daasds");
            //_signaling?.katil(streamId);
            //_signaling?.join(streamId);
          },child: Container(padding: EdgeInsets.all(20),decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),color: Colors.green),child: Text("join")),),),
        ],
      ),
    );
  }
}

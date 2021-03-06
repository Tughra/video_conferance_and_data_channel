import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:core';
import 'signaling.dart';

class CallSample extends StatefulWidget {
  static String tag = 'call_sample';

  final String ip;
  final String type;
  final String id;

  CallSample({Key? key, required this.ip, required this.type, required this.id})
      : super(key: key);

  @override
  _CallSampleState createState() =>
      _CallSampleState(serverIP: ip, serverType: type, streamId: id);
}

class _CallSampleState extends State<CallSample> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  var _selfId;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  final String serverIP;
  final String serverType;
  final String streamId;

  _CallSampleState(
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
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void _connect() async {
    print("Connect call to $serverIP");
    if (_signaling == null) {
      _signaling = Signaling(serverIP, serverType, streamId)..connect();

      _signaling?.onStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.CallStateNew:
            this.setState(() {
              _inCalling = true;
            });
            break;
          case SignalingState.CallStateBye:
            this.setState(() {
              _localRenderer.srcObject = null;
              _remoteRenderer.srcObject = null;
              _inCalling = false;
              Navigator.pop(context);
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

      _signaling?.onPeersUpdate = ((event) {
        this.setState(() {
          _selfId = event['self'];
          _peers = event['peers'];
        });
      });

      /*_signaling.onLocalStream = ((stream) {// changed because we wanted in bigger screen when we do stream or play a stream. useful when using p2p call.
        _localRenderer.srcObject = stream;
      });*/

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

  _switchCamera() {
    _signaling?.switchCamera();
  }

  _muteMic() {
    _signaling?.muteMic();
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
        title: Text(serverType == 'play' ? 'Playing' : 'Publishing'),
        actions: <Widget>[
          /*IconButton(       // if settings are required while in action, this could be useful.
            icon: const Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),*/
        ],
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
                    if (serverType == 'publish')
                      FloatingActionButton(
                        heroTag: "0",
                        child: const Icon(Icons.switch_camera),
                        onPressed: _switchCamera,
                      ),
                    FloatingActionButton(
                      heroTag: "1",
                      onPressed: _hangUp,
                      tooltip: 'Hangup',
                      child: Icon(Icons.call_end),
                      backgroundColor: Colors.pink,
                    ),
                    if (serverType == 'publish')
                      FloatingActionButton(
                        heroTag: "2",
                        child: const Icon(Icons.mic_off),
                        onPressed: _muteMic,
                      )
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
              },child: Container(padding: EdgeInsets.all(20),color: Colors.green,child: Text("join")),),),
              ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(0.0),
                  itemCount: (_peers != null ? _peers.length : 0),
                  itemBuilder: (context, i) {
                    return _buildRow(context, _peers[i]);
                  }),
            ],
          ),
    );
  }
}
/*
  takeConfiguration(idOfStream, configurationSdp, typeOfConfiguration, idMapping)async{
    var streamId = idOfStream;
    var type = typeOfConfiguration;
    var sdp = configurationSdp;
    var isTypeOffer = (type == 'offer');
    var dataChannelMode = 'publish';
    if(isTypeOffer) {
      dataChannelMode = "play";
    }
    this.idMapping[streamId] = idMapping;
    if (this.onStateChange != null) {
      this.onStateChange!(SignalingState.CallStateNew);
    }
    _peerConnections[streamId] =
    await _createPeerConnection(streamId, dataChannelMode, false);
    await _peerConnections[streamId]!
        .setRemoteDescription(new RTCSessionDescription(sdp, type));
    for (int i = 0; i < _remoteCandidates.length; i++) {
      await _peerConnections[streamId]!.addCandidate(_remoteCandidates[i]);
    }
    _remoteCandidates = [];
    if (isTypeOffer)
      await _createAnswerAntMedia(streamId, _peerConnections[streamId]!, 'play');
  }

 */
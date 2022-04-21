import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'dart:core';
import 'signaling.dart';

class MultiPeerConferance extends StatefulWidget {
  final String ip;
  final String type;
  final String id;

  MultiPeerConferance({Key? key, required this.ip, required this.type, required this.id})
      : super(key: key);

  @override
  _MultiPeerConferanceState createState() =>
      _MultiPeerConferanceState(serverIP: ip, serverType: type, roomName: id);
}

class _MultiPeerConferanceState extends State<MultiPeerConferance> {
  Signaling? _signaling;
  List<String>messages=[];
  String? peerStreamId;
  String? _selfId;
  TextEditingController _controller=TextEditingController();
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer2 = RTCVideoRenderer();
  late Timer roomTimer;
  bool _inCalling = false;
  final String serverIP;
  final String serverType;
  final String roomName;
  late String publishStream;
  List<dynamic> streamsList=[];
  _MultiPeerConferanceState(
      {Key? key,
        required this.serverIP,
        required this.serverType,
        required this.roomName});

  @override
  initState() {
    super.initState();
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _remoteRenderer2.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _remoteRenderer2.dispose();
  }

  void _connect() async {
    print("Connect call to $serverIP");
    if (_signaling == null) {
      _signaling = Signaling(serverIP, serverType, roomName)..connect();
        _signaling?.callback=(String info,Map obj){
        if(info=="joinedTheRoom"){
          _signaling?.publishSfu(streamID: obj['streamId'],video: true,audio: true);
          publishStream=obj['streamId'];
          streamsList = obj["streams"];
          //peerStreamId
          roomTimer=Timer.periodic(Duration(seconds: 5), (timer) {
            _signaling?.getRoomInfo(roomName, publishStream);
            print(publishStream);
          });
          if (streamsList.isNotEmpty) {
            _signaling?.startPlayingSfuAntMedia(streamID: streamsList.first, room: roomName);
            obj["streams"].forEach((item) {
            print("Stream joined with ID: "+item);

            });
          }
         /*
          if(streamsList.length > 0){
            dominantSpeakerFinderId = setInterval(() => {
            webRTCAdaptor.getSoundLevelList(streamsList);
            }, 200);
          }
          */
        }
        else if (info == "newStreamAvailable") {
          print("----newStreamAvailable-----");
          /*
          Timer.periodic(new Duration(seconds: 5), (timer) {
   print(timer.tick.toString());
});
           */
          /*
          if(dominantSpeakerFinderId == null){
            dominantSpeakerFinderId = setInterval(() => {
            webRTCAdaptor.getSoundLevelList(streamsList);
            }, 200);
          }
           */
        }
        else if (info == "streamInformation") {
          print("stream information girdi");
          _signaling?.startPlayingSfuAntMedia(streamID:obj['streamId'],room:roomName );
        }
        else if (info == "roomInformation") {
          //Checks if any new stream has added, if yes, plays.
        /*
          for(var str in obj["streams"]){
            if(!streamsList.includes(str)){
             _signaling?.startPlayingSfuAntMedia(streamID: obj["streams"][0], room: roomName);
            }
          }
         */
          if(streamsList.isEmpty){
            streamsList=obj["streams"];
            //if(streamsList.isNotEmpty&&(streamsList.first!=obj["streams"][0]))
          if(streamsList.isNotEmpty)_signaling?.startPlayingSfuAntMedia(streamID: obj["streams"][0], room: roomName);
          }
      }
        else if (info == "data_received") {
          print("****data_received****");
          var data = obj["data"];
          print(data.toString());
          /*
          if (data instanceof ArrayBuffer) {
            handleImageData(data);
          } else if (data instanceof Blob) {
            data.arrayBuffer().then((buffer) => handleImageData(buffer));
          } else {
            handleTextMessage(data);
          }
           */
        //  handleTextMessage(data);
            }};
      _signaling?.onDataChannel=(dataChannel){
        dataChannel.onMessage = (message) {
          if (message.type == MessageType.text) {
            print(message.text);
            handleTextMessage(message.text);
            print("---000---");
          } else {
            print("---222---");
            // do something with message.binary
          }
        };
        // or alternatively:
        dataChannel.messageStream.listen((message) {
          if (message.type == MessageType.text) {
            print(message.text);
            print("---333---");
          } else {
            print("---444---");
            // do something with message.binary
          }
        });

        dataChannel.send(RTCDataChannelMessage('Hello!'));
        dataChannel.send(RTCDataChannelMessage.fromBinary(Uint8List(5)));
      };

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
              _remoteRenderer2.srcObject = null;
              _inCalling = false;
              roomTimer.cancel();
              if(Get.currentRoute=="/MultiPeerConferance")Get.back();
              print("-----CallStateBye-----");
              //Navigator.pop(context);
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

   /*
      _signaling?.onPeersUpdate = ((event) {
        this.setState(() {
          _selfId = event['self'];
          _peers = event['peers'];
        });
      });
    */

      /*_signaling.onLocalStream = ((stream) {// changed because we wanted in bigger screen when we do stream or play a stream. useful when using p2p call.
        _localRenderer.srcObject = stream;
      });*/

      _signaling?.onLocalStream = ((stream) {
        if(mounted) setState(() {
          _localRenderer.srcObject = stream;
        });
      });

      _signaling?.onAddRemoteStream = ((stream) {
        if(mounted)  setState(() {
          _remoteRenderer.srcObject = stream;
        });
      });
      _signaling?.onRemoveRemoteStream = ((stream) {
        _remoteRenderer.srcObject = null;
      });
    }

    }
    Future sendData(String data) async{
      _signaling?.sendData(publishStream, data);
   /*
    try {
      var iceState = webRTCAdaptor.iceConnectionState(streamNameBox.value);
      if (
      iceState != null &&
          iceState != "failed" &&
          iceState != "disconnected"
      ) {
       // webRTCAdaptor.sendData(streamNameBox.value, data);
      } else {
        alert("WebRTC connection is not active. Please click start first");
      }
    } catch (exception) {
      console.error(exception);
      alert(
          "Message cannot be sent. Make sure you've enabled data channel on server web panel"
      );
    }
    */
  }
     createNewMessage(message, date, sentByUs) {
    if (message.toString().trim()== "") {
      return false;
    }
    setState(() {
      messages.add(message);
    });
  /*
      if (sentByUs) {
      $(
          '<div class="outgoing_msg row"><div class="col"><div class="sent_msg">	<p>' +
              message +
              '</p><span class="time_date">' +
              date +
              "</span></div></div></div>"
      ).appendTo($("#all_messages"));
    } else {
      $(
          '<div class="incoming_msg row"><div class="col" ><div class="received_msg"><div class="received_withd_msg"><p>' +
              message +
              '</p><span class="time_date">' +
              date +
              "</span></div></div></div>"
      ).appendTo($("#all_messages"));
    }
   */
  }
  void handleTextMessage(String data) {
    print("-------handle message--------");
    log(data.toString());
   // var messageObj = data;//Json.parse(data);
    var dateObj = new DateTime.now();

    createNewMessage(
        data,
        dateObj.toString(),
        false
    );
  }
  Widget messageWidget({required String message,required String time}){
    return Container(child: Column(
      children: [
        Card(child: Text(message),),
        Text(time)
      ],
    ),);
  }
  _invitePeer(context, peerId, use_screen) async {
    if (_signaling != null && peerId != _selfId) {
      _signaling?.invite(peerId, 'video', use_screen);
    }
  }

  _hangUp() {
    if (_signaling != null) {
      _signaling?.leaveRoom(roomName);
      roomTimer.cancel();
    }
  }

  _switchCamera() {
    _signaling?.switchCamera();
  }

  _muteMic() {
    _signaling?.muteMic();
    print("Mute micc");
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Conference"),
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
              mainAxisAlignment:MainAxisAlignment.spaceBetween,

              children: <Widget>[
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
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                  width: 90,
                  height: 140,
                  child: RTCVideoView(_remoteRenderer,objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,),
                  decoration: BoxDecoration(color: Colors.black54),
                ),
                /*
                TextButton(onPressed: (){
                  _signaling?.startPlayingSfuAntMedia(streamID: "LXiSeaIVIuEVVyev",room: "bil");
                  //KKsECkJVEnTsDxwB iphone
                }, child: Text("İphoneda Bas ",style: TextStyle(fontSize: 12),),),
                TextButton(onPressed: (){
                  _signaling?.startPlayingSfuAntMedia(streamID: "OklTvlFNCvZjtGhk",room: "bil");
                  //KKsECkJVEnTsDxwB iphone
                }, child: Text("Lenovada Bas",style: TextStyle(fontSize: 12))),
                 */
                Container(    // useful when in a p2p call. small display for self video.
                  width: 90,
                  height:140,
                  child: RTCVideoView(_localRenderer),
                  decoration: BoxDecoration(color: Colors.black54),
                ),
              ],
            ),
            Align(alignment: Alignment.bottomCenter,child: Container(height: 500,child: ListView.builder(shrinkWrap: true,itemBuilder: (context, index) => messageWidget(message: messages[index], time: "12.01.2022"),itemCount: messages.length,))),
            Align(alignment: Alignment.center,child: Container(margin: EdgeInsets.symmetric(horizontal: 20),padding: EdgeInsets.symmetric(vertical: 10,horizontal: 100),decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),gradient: LinearGradient(colors: [Colors.blue,Colors.yellow,Colors.white])),child: TextField(controller: _controller,onSubmitted:(e){
              print("Göder mesaj");
              //final List<int> codeUnits = "lalalallalalala".codeUnits;
              if(streamsList.isNotEmpty) sendData(e).then((value) => _controller.clear());
            },)),)
          ]),
        );
      })
          : Stack(
        children: [
          Align(alignment: Alignment.center,child: InkWell(onTap: null,child: Container(padding: EdgeInsets.symmetric(vertical: 10,horizontal: 100),decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),gradient: LinearGradient(colors: [Colors.purple,Colors.pink,Colors.white])),child: Text("Awaiting Participant...",style: TextStyle(color: Colors.white,fontWeight: FontWeight.bold),)),),),
          /*
                      ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: (_peers != null ? _peers.length : 0),
              itemBuilder: (context, i) {
                return _buildRow(context, _peers[i]);
              }),
             */
        ],
      ),
    );
  }
}

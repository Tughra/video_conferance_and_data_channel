import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'random_string.dart';

import '../utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';

enum SignalingState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

/*
 * callbacks for Signaling API.
 */
typedef void SignalingStateCallback(SignalingState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);
typedef void SocketCallback(String info,Map<String,dynamic> obj);
class Signaling {
  late SocketCallback callback;
  JsonEncoder _encoder = new JsonEncoder();
  JsonDecoder _decoder = new JsonDecoder();
  String _selfId = randomNumeric(6);
  SimpleWebSocket? _socket;
  List streamList=[];
  var _sessionId;
  var _host;
  List<RTCVideoRenderer>? remoteRendererList;
  //var _port = '/WebRTCAppEE/websocket';
  var _peerConnections = new Map<String, RTCPeerConnection>();
  var _dataChannels = new Map<String, RTCDataChannel>();
  var _remoteCandidates = [];
  var _turnCredential;
  var _streamId;
  var _type;
  var _mute = false;
  bool dataChannelEnabled =true;
  int pingTimerId = -1;
  MediaStream? _localStream;
  List<MediaStream>? _remoteStreams = [];
  SignalingStateCallback? onStateChange;
  StreamStateCallback? onLocalStream;
  StreamStateCallback? onAddRemoteStream;
  StreamStateCallback? onRemoveRemoteStream;
  OtherEventCallback? onPeersUpdate;
  DataChannelMessageCallback? onDataChannelMessage;
  DataChannelCallback? onDataChannel;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
      /*
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
       */
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true,},
    ],
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [
    ],
  };

  final Map<String, dynamic> _dc_constraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  Signaling(this._host, this._type, this._streamId);

  close() async{
   /* if (_localStream != null) {
      _localStream?.dispose();
      _localStream = null;
      onceki
    }*/
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
    _localStream = null;
    }
    _peerConnections.forEach((key, pc) {
      pc.close();
      _dataChannels.forEach((key, dc) {
        dc.close();
      });
    });
    if (_socket != null) _socket?.close();
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void muteMic() {
    if (_localStream != null) {
      bool enabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !enabled;
    }
  }

  void invite(String peer_id, String media, use_screen) {
    this._sessionId = this._selfId + '-' + peer_id;

    if (this.onStateChange != null) {
      this.onStateChange!(SignalingState.CallStateNew);
    }

    _createPeerConnection(peer_id, media, use_screen,openCamera: true,dataChannelMode: "publish").then((pc) {
      _peerConnections[peer_id] = pc;
      if (media == 'data') {
        _createDataChannel(peer_id, pc);
      }
      _createOfferAntMedia(peer_id, pc, media);
    });
  }

  void closePeer2Peer(String streamId) {
    _sendAntMedia({"command": "leave", "streamId": streamId});
  }

  void leaveRoom(String room) {
    _sendAntMedia({"command": "leaveFromRoom", "room": room});
  }

  void bye() {
    var request = new Map();
    request['command'] = 'stop';
    request['streamId'] = _streamId;
    _sendAntMedia(request);
  }

  void onMessage(message) async {
    print("Gelen mesaj soketten" + message.toString());
    Map<String, dynamic> mapData = message;
    var command = mapData['command'];
    print('current command is ' + command);

    switch (command) {
      case 'start':
        {
          print("starta girdiiiiiiii");
          String id = mapData['streamId'];
          print(id);
          if (this.onStateChange != null) {
            this.onStateChange!(SignalingState.CallStateNew);
          }
            _peerConnections[id] = await _createPeerConnection(id, 'play', false,openCamera: true,dataChannelMode:"publish");
            await _createOfferAntMedia(id, _peerConnections[id]!, 'play');


          print("--------publishhh---------");
        }
        break;
      case 'takeConfiguration':
        {
          print("--------takeConfiguration gelen----------");
          var id = mapData['streamId'];
          var type = mapData['type'];
          var sdp = mapData['sdp'];
          var isTypeOffer = (type == 'offer');
          var dataChannelMode = 'publish';
          if (isTypeOffer) dataChannelMode = 'play';
          if (isTypeOffer) {
            print("---- is ty offer true ----");
            if (this.onStateChange != null) {
              this.onStateChange!(SignalingState.CallStateNew);
            }
           if(_peerConnections[id]==null) {
             print("peer connection id null dı ");
              _peerConnections[id] =
                  await _createPeerConnection(id, "play", false,openCamera: false,dataChannelMode:"play");
            }
          }
          await _peerConnections[id]!
              .setRemoteDescription(new RTCSessionDescription(sdp, type));
          for (int i = 0; i < _remoteCandidates.length; i++) {
            await _peerConnections[id]!.addCandidate(_remoteCandidates[i]);
          }
          _remoteCandidates = [];
          if (isTypeOffer)
            await _createAnswerAntMedia(id, _peerConnections[id]!, 'play');
        }
        break;
      case 'stop':
        {
          _closePeerConnection(_streamId);
        }
        break;

      case 'takeCandidate':
        {
          print(mapData);
          print("-----------take Candiate gelen------------");
          String id = mapData['streamId'];
          print(id);
          RTCIceCandidate candidate = new RTCIceCandidate(
              mapData['candidate'], mapData['id'], mapData['label']);
          if (_peerConnections[id] != null) {
            await _peerConnections[id]!.addCandidate(candidate);
          } else {
            _remoteCandidates.add(candidate);
            print(_remoteCandidates.first);
            print("--------take candidate----------");
          }
        }
        break;

      case 'error':
        {
          this.callback(mapData['definition'], mapData);
          print(mapData['definition']);
        }
        break;

      case 'notification':
        {
          this.callback(mapData['definition'], mapData);
          if (mapData['definition'] == 'play_finished' ||
              mapData['definition'] == 'publish_finished') {
            _closePeerConnection(_streamId);
          } else if (mapData['definition'] == 'joinedTheRoom') {
            print("notification starta girdiiiiiiii");
            streamList = mapData['streams'];
          }
        }
        break;
      case 'streamInformation':
        {
         // this.callback(mapData['definition'], mapData);
         // print(command + '' + mapData);
          print("----streamInformation-------");
        }
        break;
      case 'roomInformation':
        {
          this.callback("roomInformation", mapData);
          print(mapData);
          print("----roomInformation-------");
        }
        break;
      case 'pong':
        {
          //this.callback(mapData['definition'], mapData);
          print(command);
          print("----pong-------");
        }
        break;
      case 'trackList':
        {
          this.callback(mapData['definition'], mapData);
          print(mapData);
          print("------trackList-------");
        }
        break;
      case 'connectWithNewId':
        {
          this.callback(mapData['definition'], mapData);
          print("------- with new idd");
          join(_streamId);
          print("-----connectWithNewId------");
        }
        break;
      case 'peerMessageCommand':
        {
          this.callback(mapData['definition'], mapData);
          print(mapData);
          print("-------peerMessageCommand--------");
        }
        break;
    }
  }

  void connect() async {
    //var url = '$_host$_port';
    var url = '$_host';
    _socket = SimpleWebSocket(url);

    print('connect to $url');

    /*if (_turnCredential == null) { //if turn is required for some reason, this code segment is useful.
      try {
        _turnCredential = await getTurnCredential(_host, _port);
        /*{
            "username": "1584195784:mbzrxpgjys",
            "password": "isyl6FF6nqMTB9/ig5MrMRUXqZg",
            "ttl": 86400,
            "uris": ["turn:127.0.0.1:19302?transport=udp"]
          }
        */
        _iceServers = {
          'iceServers': [
            {
              'url': _turnCredential['uris'][0],
              'username': _turnCredential['username'],
              'credential': _turnCredential['password']
            },
          ]
        };
      } catch (e) {}
    }*/

    _socket?.onOpen = () {
     /*
      this.pingTimerId=Timer.periodic(Duration(seconds:3), (timer) {
        sendPing();
        }).tick;
      */
      print('onOpen');
      print(_type);
      this.onStateChange!(SignalingState.ConnectionOpen);
      if (_type == "play")
        _startPlayingAntMedia(_streamId);
      else if (_type == "publish") {
        _startStreamingAntMedia(_streamId);
      } else if (_type == "peer2peer") {
        joinP2P(_streamId);
      } else {
        joinOrCreateRoom(_streamId);
      }
    };

    _socket?.onMessage = (message) {
      print('Received data: ' + message);
      JsonDecoder decoder = new JsonDecoder();
      this.onMessage(decoder.convert(message));
    };

    _socket?.onClose = (int? code, String? reason) {
      print('Closed by server [$code => $reason]!');
      if (this.onStateChange != null) {
        this.onStateChange!(SignalingState.ConnectionClosed);
      }
    };

    await _socket?.connect();
  }

  Future<MediaStream> createStream(media, user_screen) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth':
              '640', // Provide your own width, height and frame rate here
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    MediaStream stream = user_screen
        ? await navigator.mediaDevices.getDisplayMedia(mediaConstraints)
        : await navigator.mediaDevices.getUserMedia(mediaConstraints);
    onLocalStream?.call(stream);
    /*
    onceki bu
      if (this.onLocalStream != null) {
      this.onLocalStream!(stream);
    }
     */
    return stream;
  }

  _createPeerConnection(id, media, userScreen,{required bool openCamera,required String  dataChannelMode}) async {
    if (this._peerConnections[id] == null){
      print("-*-");
    }
    if (_type != 'play') //if playing, it won't open the camera.

    if (media != 'data'&&openCamera==true) _localStream = await createStream(media, userScreen);
    print(_localStream?.getVideoTracks().first);
    print("---------------localVideoTrack----------------");
    RTCPeerConnection pc = await createPeerConnection(_iceServers, _config);
    if (media != 'data' && _type != 'play'&&this._peerConnections[id] == null &&openCamera==true) pc.addStream(_localStream!);
    pc.onIceCandidate = (candidate) {
      print(candidate.toMap());
      print("----cereatePeerConnection-----");
      var request = new Map();
      request['command'] = 'takeCandidate';
      request['streamId'] = id;
      request['label'] = candidate.sdpMLineIndex;
      request['id'] = candidate.sdpMid;
      request['candidate'] = candidate.candidate;
      _sendAntMedia(request);
    };
    pc.onIceConnectionState = (state) {};
      pc.onAddStream = (stream) {
        print("----on add remote streammmm----");
        if (this.onAddRemoteStream != null) this.onAddRemoteStream!(stream);
        _remoteStreams?.add(stream);
      };
    pc.onRemoveStream = (stream) {
      if (this.onRemoveRemoteStream != null) this.onRemoveRemoteStream!(stream);
      _remoteStreams?.removeWhere((it) {
        return (it.id == stream.id);
      });
    };
    if(this.dataChannelEnabled==true){
      print("**********dataChannelEnabled***********");
      await _createDataChannel(id, pc);
      // skip initializing data channel if it is disabled
      /*
      if (dataChannelMode == "publish") {
        //open data channel if it's publish mode peer connection
        const dataChannelOptions = {
          "ordered": true,
        };
        print("dataChannel üretildi");
      await _createDataChannel(id, pc);
      } else if(dataChannelMode == "play") {
        print("dataChannel oluşmadı");
        //in play mode, server opens the data channel
      }
      else {
        print("dataChannel üretildi 2 ");
        //for peer mode do both for now
        const dataChannelOptions = {
          "ordered": true,
        };
        await  _createDataChannel(id, pc);
      }
       */

    }


    return pc;
  }

  void setRemoteRendererList(List<RTCVideoRenderer> rendererList) {
    this.remoteRendererList = rendererList;
    //sonradan eklendi
  }

  void _onDataChannelSonra(RTCDataChannel dataChannel) {
    dataChannel.onMessage = (message) {
      if (message.type == MessageType.text) {
        print(message.text);
      } else {
        // do something with message.binary
      }
    };
    // or alternatively:
    dataChannel.messageStream.listen((message) {
      if (message.type == MessageType.text) {
        print(message.text);
      } else {
        // do something with message.binary
      }
    });

    dataChannel.send(RTCDataChannelMessage('Hello!'));
    dataChannel.send(RTCDataChannelMessage.fromBinary(Uint8List(5)));
  }
  initDataChannel(streamId,RTCDataChannel dataChannel){
    _dataChannels[streamId] = dataChannel;
    if (this.onDataChannel != null) this.onDataChannel!(dataChannel);
    dataChannel.onDataChannelState=(state){
      switch(state) {
        case RTCDataChannelState.RTCDataChannelClosed: {
         print("-RTCDataChannelClosed-");
        }
        break;

        case RTCDataChannelState.RTCDataChannelOpen: {
          print("-RTCDataChannelOpen-");
        }
        break;
        case RTCDataChannelState.RTCDataChannelClosing: {
          print("-RTCDataChannelClosing-");
        }
        break;
        case RTCDataChannelState.RTCDataChannelConnecting: {
          print("-RTCDataChannelConnecting-");
        }
        break;
      }
    };
    dataChannel.onMessage = (event){
      Map<String,dynamic> obj = {
        "streamId": streamId,
        "data": event.text,
      };
      print(event.text);
      print("--------data geldiiii---------");
      this.callback("data_received", obj);
    };
  }
  _addDataChannel(id, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      print("----------*-----------${data.text}--------------*------------");
      if (this.onDataChannelMessage != null) {
        print("onDataChannelMessage nuu değil");
        this.onDataChannelMessage!(channel, data);
      }
      this.callback("data_received", {"data":data.text});

    };
    print("***_addDataChannel***");
    _dataChannels[id] = channel;
    if (this.onDataChannel != null) this.onDataChannel!(channel);
  }

  _createDataChannel(String id, RTCPeerConnection pc, {label: 'dataChannel'}) async {
    print("***_createDataChannel***");
    print(id);

    RTCDataChannelInit dataChannelDict =  RTCDataChannelInit();
    dataChannelDict.id = 1;
    dataChannelDict.ordered = true;
    dataChannelDict.maxRetransmitTime = -1;
    dataChannelDict.maxRetransmits = -1;
    dataChannelDict.protocol = 'sctp';
    dataChannelDict.negotiated = false;
    RTCDataChannel channel = await pc.createDataChannel(label, dataChannelDict);
    pc.onDataChannel=onDataChannel;
    initDataChannel(id, channel);
   // _addDataChannel(id, channel);
  }

  _createOfferAntMedia(String id, RTCPeerConnection pc, String media) async {
    print("-----------_createOfferAntMedia------------");
    try {
      RTCSessionDescription s = await pc
          .createOffer(media == 'data' ? _dc_constraints : _constraints);
      pc.setLocalDescription(s);
      print('s.type is:  ' + s.type.toString());
      var request = new Map();
      request['command'] = 'takeConfiguration';
      request['streamId'] = id;
      request['type'] = s.type;
      request['sdp'] = s.sdp;
      _sendAntMedia(request);
    } catch (e) {
      print(e.toString());
    }
  }


  _createAnswerAntMedia(String id, RTCPeerConnection pc, media) async {
    try {
      RTCSessionDescription s = await pc
          .createAnswer(media == 'data' ? _dc_constraints : _constraints);
      pc.setLocalDescription(s);
      print('s.type is:  ' + s.type.toString());
      var request = new Map();
      request['command'] = 'takeConfiguration';
      request['streamId'] = id;
      request['type'] = s.type;
      request['sdp'] = s.sdp;
      _sendAntMedia(request);
    } catch (e) {
      print(e.toString());
    }
  }

  _sendAntMedia(Map request) {
    _socket?.send(_encoder.convert(request));
  }

  _closePeerConnection(streamId) {
    var id = streamId;
    print('bye: ' + id);
    if (_mute) muteMic();
    if (_localStream != null) {
      _localStream?.dispose();
      _localStream = null;
    }
    var pc = _peerConnections[id];
    if (pc != null) {
      pc.close();
      _peerConnections.remove(id);
    }
    var dc = _dataChannels[id];
    if (dc != null) {
      dc.close();
      _dataChannels.remove(id);
    }
    this._sessionId = null;
    if (this.onStateChange != null) {
      this.onStateChange!(SignalingState.CallStateBye);
    }
  }
/*
  Future<void> _cleanSessions() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess.pc?.close();
      await sess.dc?.close();
    });
    _sessions.clear();
  }
 */

  joinOrCreateRoom(String roomID) {
    print("--------"+roomID);
    _sendAntMedia({"command": "joinRoom", "room": roomID,"mode": "mcu"});
  }

  publishSfu(
      {required String streamID, required bool video, required bool audio}) {
    _sendAntMedia({
      "command": "publish",
      "streamId": streamID,
      "video": video,
      "audio": audio
    });
  }

  join(streamId) {
    var request = new Map();
    request['command'] = 'join';
    request['streamId'] = streamId;
    request['multiPeer'] = false;/// false du
    request['mode'] = 'both';//'play';
    print("gittimi");
    _sendAntMedia(request);
  }

  joinP2P(streamId) {
    var request = {
      "command": "join",
      "streamId": streamId,
    };
    print("gittimi");
    _sendAntMedia(request);
  }

  _startStreamingAntMedia(streamId) {
    var request = new Map();
    request['command'] = 'publish';
    request['streamId'] = streamId;
    request["streamName"]="Guest";
    request['token'] = '';
    request['video'] = true;
    request['audio'] = true;
    _sendAntMedia(request);
  }

  _startPlayingAntMedia(streamId) {
    var request = new Map();
    request['command'] = 'play';
    request['streamId'] = streamId;
   // request['token'] = '';
    _sendAntMedia(request);
  }

  startPlayingSfuAntMedia({required String streamID,required String room}) {
    _sendAntMedia({
      "command": "play",
      "streamId": streamID,
      "room": room,
      "viewerInfo": "",
    });
  }
  getRoomInfo(roomName,streamId)
  {
    _sendAntMedia(
        {
          "command" : "getRoomInfo",
          "streamId" : streamId,
          "room": roomName,
        }
    );
  }
  sendPing() {
    _sendAntMedia({
      "command" : "ping"
    });
  }
  clearPingTimer(){
    if (this.pingTimerId != -1) {
      this.pingTimerId = -1;
    }
  }
  getTracks(streamId)
  {
   // this.playStreamId.push(streamId);
  _sendAntMedia(    {
    "command" : "getTrackList",
    "streamId" : streamId,
  });
  }



  sendData(streamId, String message)
  {
    print("Göder mesaj tetikleme");
    print(streamId);
    _dataChannels[streamId]?.send(RTCDataChannelMessage(message)).then((value) => print("mesaj gönderildi"));
    /*
    var CHUNK_SIZE = 16000;
    var length = data.length || data.size || data.byteLength;
    var sent = 0;

    if(typeof data === 'string' || data instanceof String){
      _dataChannels[streamId]?.send(data);
    }
    else {
      var token = Math.floor(Math.random() * 999999);
      let header = new Int32Array(2);
      header[0] = token;
      header[1] = length;

      dataChannel.send(header);

      var sent = 0;
      while(sent < length) {
        var size = Math.min(length-sent, CHUNK_SIZE);
        var buffer = new Uint8Array(size+4);
        var tokenArray = new Int32Array(1);
        tokenArray[0] = token;
        buffer.set(new Uint8Array(tokenArray.buffer, 0, 4), 0);

        var chunk = data.slice(sent, sent+size);
        buffer.set(new Uint8Array(chunk), 4);
        sent += size;

        dataChannel.send(buffer);
      }
    }
     */
  }

  /*
  getSoundLevelList(streamsList){
		for(let i = 0; i < streamsList.length; i++){
			this.soundLevelList[streamsList[i]] = this.soundMeters[streamsList[i]].instant.toFixed(2);
		}
		this.callback("gotSoundList" , this.soundLevelList);
	}
   */
}

/*
  _createPeerConnection(id, media, userScreen) async {
    if (this._peerConnections[id] == null){
      print("-*-");
    }
    if (_type != 'play') //if playing, it won't open the camera.
    if (media != 'data') _localStream = await createStream(media, userScreen);
    print(_localStream?.getVideoTracks().first);
    print("---------------localVideoTrack----------------");
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': sdpSemantics}
    },_config);
    if (media != 'data') {
      switch (sdpSemantics) {
        case 'plan-b':
          pc.onAddStream = (MediaStream stream) {
            onAddRemoteStream?.call(stream);
            _remoteStreams?.add(stream);
          };
          await pc.addStream(_localStream!);
          break;
        case 'unified-plan':
        // Unified-Plan
          pc.onTrack = (event) {
            if (event.track.kind == 'video') {
              onAddRemoteStream?.call(event.streams[0]);
            }
          };
          _localStream!.getTracks().forEach((track) {
            pc.addTrack(track, _localStream!);
          });
          break;
      }
    }
  //  if (media != 'data' && _type != 'play'&&this._peerConnections[id] == null) pc.addStream(_localStream!);
    pc.onIceCandidate = (candidate) {
      print(candidate.toMap());
      print("----cereatePeerConnection-----");
      var request = new Map();
      request['command'] = 'takeCandidate';
      request['streamId'] = id;
      request['label'] = candidate.sdpMLineIndex;
      request['id'] = candidate.sdpMid;
      request['candidate'] = candidate.candidate;
      _sendAntMedia(request);
    };
    pc.onIceConnectionState = (state) {};
    try{
      pc.onAddStream = (stream) {
        print("----on add remote streammmm----");
        if (this.onAddRemoteStream != null) this.onAddRemoteStream!(stream);
        _remoteStreams?.add(stream);
      };
    }catch(e){
      print("Hata on add remote streammmm "+e.toString());
    }


    pc.onRemoveStream = (stream) {
      if (this.onRemoveRemoteStream != null) this.onRemoveRemoteStream!(stream);
      _remoteStreams?.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    pc.onDataChannel = (channel) {
      _addDataChannel(id, channel);
    };

    return pc;
  }

 */
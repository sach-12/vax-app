import 'dart:convert';
import 'package:http/http.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vax_app/services/localdata.dart';
import 'package:telephony/telephony.dart';

backgroundMessageHandler(SmsMessage message) async {
  //Handle background message
  String? text = message.body;
  print("In handler:  $text");
}

class ApiCalls {

  final telephony = Telephony.instance;

  // Class Attributes
  Map<String, String> headers = {
    'Accept-Language': 'en-IN',
    'Content-Type': 'application/json',
    'origin': 'https://selfregistration.cowin.gov.in/',
    'referer': 'https://selfregistration.cowin.gov.in/',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.95 Safari/537.36'
  };
  late String? txnId;
  late String? token;
  late List<dynamic>? benList;
  late String otp;

  void _listen() async {
    bool? permissionsGranted = await telephony.requestSmsPermissions;
    telephony.listenIncomingSms(
      onNewMessage: (message) {
        String? text = message.body?.substring(37, 43);
        if (text == null) {
          text = '';
        }
        otp = text;
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }


  // Class methods

  Future<List<dynamic>> centers(List<int> pincodeList) async {
    DateTime tomorrowDate = DateTime.now().add(Duration(days: 1));
    String tomorrow = "${tomorrowDate.day}-${tomorrowDate.month}-${tomorrowDate.year}";
    DateTime dayAfterDate = DateTime.now().add(Duration(days: 2));
    String dayAfter = "${dayAfterDate.day}-${dayAfterDate.month}-${dayAfterDate.year}";
    List<String> dateList = [tomorrow, dayAfter];
    List<dynamic> sessions = [];
    await Future.forEach((dateList), (date) async{
      await Future.forEach(pincodeList, (pincode) async {
        String url = 'https://cdn-api.co-vin.in/api/v2/appointment/sessions/public/findByPin?pincode=$pincode&date=$date';
        Response response = await get(
            Uri.parse(url),
            headers: headers
        );
        if(response.statusCode == 200){
          var resp = jsonDecode(response.body);
          sessions.add(resp['sessions']);
        }
      });
    });
    List<dynamic> centers = [];
    sessions.forEach((centersList) {
      centersList.forEach((center) {
        if(center['available_capacity'] > 9){
          centers.add(center);
        }
      });
    });
    return centers;
  }


  Future<dynamic> getCenters(double lat, double long) async {
    String url = 'https://cdn-api.co-vin.in/api/v2/appointment/centers/public/findByLatLong?lat=$lat&long=$long';
    Response response = await get(
        Uri.parse(url),
        headers: headers
    );

    if (response.statusCode == 200) {
      var resp = jsonDecode(response.body);
      return resp['centers'];
    }
  }

  Future<void> getOtp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    User user = getUser(prefs.getString('user').toString());
    int? mobile = user.phNo;
    String url = 'https://cdn-api.co-vin.in/api/v2/auth/generateMobileOTP';
    Object? data = {
      'mobile': mobile,
      'secret': 'U2FsdGVkX19PaSqxnwmqk4McfhXokocQjLHrFbskUpcV64Aoq564fJKZ6h5X4fF9iLxBavMj4znDjeIcyNfxJw=='
    };
    Response response = await post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      var resp = jsonDecode(response.body);
      txnId = resp['txnId'];
      print(txnId);
    }
  }

  Future<void> validateOtp(String otp, {int counter = 0}) async {
    //await Future.delayed(Duration(seconds: 5));
    String url = 'https://cdn-api.co-vin.in/api/v2/auth/validateMobileOtp';
    Digest encodedOtp = sha256.convert(utf8.encode(otp));
    Object? data = {
      'otp': encodedOtp.toString(),
      'txnId': txnId
    };
    Response response = await post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(data),
    );
    Map<String, dynamic> respStr = jsonDecode(response.body);
    respStr.forEach((key, value) {
      if (value == 'txnId is Required') {
        if (counter == 50) {
          print('i am done');
          return;
        }
        counter += 1;
        validateOtp(otp, counter: counter);
      }
    });
    print(response.statusCode);
    print(response.body);
    if (response.statusCode == 200) {
      var resp = jsonDecode(response.body);
      token = resp['token'];
      headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<void> getBen() async {
    await Future.delayed(Duration(seconds: 7));
    print(headers);
    String url = "https://cdn-api.co-vin.in/api/v2/appointment/beneficiaries";
    Response response = await get(
        Uri.parse(url),
        headers: headers
    );
    print(response.statusCode);
    print(response.body);
    if (response.statusCode == 200) {
      // ben = response.body;
      Map<String, dynamic> benJson = jsonDecode(response.body);
      benList = benJson['beneficiaries'];
    }
  }

  Future<Map<int, String>> schedule(int dose, String sessionId, String slot, int centerId, List<int> beneficiaries) async {
    await setToken();
    String url = 'https://cdn-api.co-vin.in/api/v2/appointment/schedule';
    Object? data = {
      'dose': dose,
      'session_id': sessionId,
      'slot': slot,
      'beneficiaries': beneficiaries,
      'center_id': centerId
    };
    Response response = await post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(data),
    );
    Map<int, String> ret = {};
    ret[response.statusCode] = response.body;
    return ret;

  }

  // Shortcut functions
  Future<void> setToken() async {
    _listen();
    await getOtp();
    Future.delayed(Duration(seconds: 5), () async {
      await validateOtp(otp);
    });

  }


}

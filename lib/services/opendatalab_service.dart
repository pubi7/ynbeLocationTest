import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

/// opendatalab.mn API-аас байгууллагын мэдээлэл хайх service
class OpendatalabService {
  static final OpendatalabService _instance = OpendatalabService._internal();
  factory OpendatalabService() => _instance;
  OpendatalabService._internal();

  /// opendatalab.mn API-аас байгууллагын мэдээлэл хайх
  /// 
  /// [registrationNumber] - Байгууллагын бүртгэлийн дугаар
  /// 
  /// Буцаах утга:
  /// - Амжилттай бол: Map<String, dynamic> with keys: name, type, registrationNumber, address, phone, email
  /// - Network алдаа бол: Map with 'error': 'network' and 'message'
  /// - API алдаа бол: Map with 'error': 'api' and 'message'
  /// - Бусад алдаа бол: Map with 'error': 'unknown' and 'message'
  /// - Мэдээлэл олдохгүй бол: null
  Future<Map<String, dynamic>?> searchOrganization(String registrationNumber) async {
    print('=== opendatalab.mn API хайлт эхэлж байна: $registrationNumber ===');
    
    try {
      final dio = Dio(BaseOptions(
        baseUrl: 'https://opendatalab.mn',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://opendatalab.mn/',
          'Origin': 'https://opendatalab.mn',
          'Accept-Language': 'mn,en-US;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
        },
      ));
      
      // opendatalab.mn вэбсайтын хайлтын API endpoint-үүдийг турших
      // Олон endpoint-үүдийг дараалан турших
      print('🌐 opendatalab.mn API endpoint-үүдийг туршиж байна: $registrationNumber');
      
      Response? response;
      DioException? lastException;
      List<String> triedEndpoints = [];
      
      // Endpoint-үүдийн жагсаалт (opendatalab.mn вэбсайтын бодит API endpoint-үүд)
      final endpoints = <Map<String, dynamic>>[
        // opendatalab.mn вэбсайтын хайлтын API - эхлээд энэ endpoint-ийг турших
        {
          'path': '/api/search',
          'params': {'q': registrationNumber},
        },
        {
          'path': '/api/info/check/getTinInfo',
          'params': {'regNo': registrationNumber},
        },
        {
          'path': '/api/entity/search',
          'params': {'regNo': registrationNumber},
        },
        {
          'path': '/search',
          'params': {'query': registrationNumber},
        },
        // /api/organization/search endpoint нь буруу parameter ашиглаж байгаа тул засах
        {
          'path': '/api/organization/search',
          'params': {'regNo': registrationNumber}, // registrationNumber биш regNo ашиглах
        },
        {
          'path': '/api/organization/search',
          'params': {'q': registrationNumber}, // q parameter-тэй турших
        },
      ];
      
      // Бүх endpoint-үүдийг турших
      for (var endpoint in endpoints) {
        final path = endpoint['path'] as String;
        final params = endpoint['params'] as Map<String, dynamic>;
        
        try {
          print('🔄 Туршиж байна: $path with params: $params');
          triedEndpoints.add('$path?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}');
          
          response = await dio.get(
            path,
            queryParameters: params,
          );
          
          print('📡 Response status: ${response.statusCode}');
          if (response.data != null) {
            print('📦 Response data type: ${response.data.runtimeType}');
          }
          
          if (response.statusCode == 200) {
            print('✅ $path endpoint амжилттай: ${response.statusCode}');
            lastException = null;
            break; // Амжилттай бол зогсох
          } else if (response.statusCode == 404) {
            print('⚠️ $path endpoint 404 алдаа гарлаа (params: $params)');
            // Дараагийн endpoint-ийг турших
            continue;
          }
        } on DioException catch (e) {
          lastException = e;
          final statusCode = e.response?.statusCode;
          print('⚠️ $path endpoint алдаа: ${e.type} - $statusCode');
          
          // 404 биш бусад алдаа бол зогсох
          if (statusCode != null && statusCode != 404) {
            break;
          }
          // 404 бол дараагийн endpoint-ийг турших
        } catch (e) {
          final endpointPath = endpoint['path'] as String;
          print('⚠️ $endpointPath endpoint бусад алдаа: $e');
          // Дараагийн endpoint-ийг турших
        }
      }
      
      // Хэрэв бүх endpoint алдаатай бол exception-ийг дахин throw хийх
      if (response == null || response.statusCode != 200) {
        if (lastException != null) {
          // 404 алдаа эсэхийг шалгах
          if (lastException.response?.statusCode == 404) {
            print('❌ Бүх endpoint-үүд 404 алдаа буцаасан. Туршсан endpoint-үүд: ${triedEndpoints.join(", ")}');
            print('⚠️ opendatalab.mn API endpoint-үүд өөрчлөгдсөн эсвэл байхгүй болсон байж магадгүй.');
            return {
              'error': 'api_not_found', 
              'message': 'opendatalab.mn API endpoint-үүд олдсонгүй. Вэбсайтын бүтэц өөрчлөгдсөн байж магадгүй. Гараар мэдээлэл оруулж болно, эсвэл https://opendatalab.mn вэбсайтаас мэдээлэл хайж болно.'
            };
          }
          throw lastException;
        } else {
          // Бүх endpoint 404 буцаасан бол
          print('❌ Бүх endpoint-үүд 404 алдаа буцаасан. Туршсан endpoint-үүд: ${triedEndpoints.join(", ")}');
          print('⚠️ opendatalab.mn API endpoint-үүд өөрчлөгдсөн эсвэл байхгүй болсон байж магадгүй.');
          return {
            'error': 'api_not_found', 
            'message': 'opendatalab.mn API endpoint-үүд олдсонгүй. Вэбсайтын бүтэц өөрчлөгдсөн байж магадгүй. Гараар мэдээлэл оруулж болно, эсвэл https://opendatalab.mn вэбсайтаас мэдээлэл хайж болно.'
          };
        }
      }
      
      print('✅ opendatalab.mn Dio response: ${response.statusCode}');
      print('Response headers: ${response.headers}');
      
      if (response.statusCode == 200) {
        final responseData = response.data;
        
        if (responseData == null) {
          print('⚠️ Response data null байна');
          return null;
        }
        
        print('Response data type: ${responseData.runtimeType}');
        print('Response data (эхний 500 тэмдэгт): ${responseData.toString().length > 500 ? responseData.toString().substring(0, 500) : responseData.toString()}');
        
        dynamic decodedData = responseData;
        
        // Response нь array байж болно
        if (decodedData is List) {
          print('Response нь array байна. Урт: ${decodedData.length}');
          if (decodedData.isEmpty) {
            print('⚠️ Array хоосон байна');
            return null;
          }
          decodedData = decodedData[0];
          print('Эхний элемент: $decodedData');
        }
        
        if (decodedData != null && decodedData is Map && decodedData.isNotEmpty) {
          print('🎉 opendatalab.mn-ээс мэдээлэл олдлоо');
          print('Data keys: ${decodedData.keys.toList()}');
          
          final data = decodedData as Map<String, dynamic>;
          
          // opendatalab.mn API response format-д тохируулах
          final organizationName = data['name'] ?? 
                                   data['organizationName'] ?? 
                                   data['companyName'] ?? 
                                   data['orgName'] ??
                                   data['businessName'] ??
                                   data['title'] ??
                                   data['company_name'] ??
                                   data['org_name'] ??
                                   data['legal_name'] ??
                                   data['legalName'] ??
                                   data['entity_name'] ??
                                   data['entityName'] ??
                                   data['companyNameMn'] ??
                                   data['companyNameEn'] ??
                                   null;
          
          if (organizationName == null || organizationName.toString().trim().isEmpty) {
            print('⚠️ Байгууллагын нэр олдсонгүй. Бүх data: $data');
            return null;
          }
          
          print('✅ Байгууллагын нэр: $organizationName');
          
          // Байгууллагын төрөл тодорхойлох
          final organizationType = data['type'] ?? 
                                  data['organizationType'] ?? 
                                  data['businessType'] ?? 
                                  data['category'] ??
                                  data['orgType'] ??
                                  data['company_type'] ??
                                  data['entity_type'] ??
                                  '';
          
          String typeDisplay = '';
          if (organizationType.toString().toLowerCase().contains('shop') || 
              organizationType.toString().toLowerCase().contains('store') ||
              organizationType.toString().toLowerCase().contains('дэлгүүр')) {
            typeDisplay = 'Дэлгүүр';
          } else if (organizationType.toString().trim().isNotEmpty) {
            typeDisplay = organizationType.toString().trim();
          } else {
            final nameLower = organizationName.toString().toLowerCase();
            if (nameLower.contains('дэлгүүр') || nameLower.contains('shop') || nameLower.contains('store')) {
              typeDisplay = 'Дэлгүүр';
            } else {
              typeDisplay = 'Байгууллага';
            }
          }
          
          return {
            'name': organizationName.toString().trim(),
            'type': typeDisplay,
            'registrationNumber': data['regNo'] ?? 
                                 data['regno'] ?? 
                                 data['registrationNumber'] ?? 
                                 data['regNumber'] ?? 
                                 data['reg_no'] ??
                                 data['reg_number'] ??
                                 data['registration_number'] ??
                                 data['tin'] ??
                                 registrationNumber,
            'address': data['address'] ?? 
                      data['location'] ?? 
                      data['fullAddress'] ?? 
                      data['registeredAddress'] ??
                      data['registered_address'] ??
                      data['address_full'] ??
                      data['legal_address'] ??
                      data['legalAddress'] ??
                      '',
            'phone': data['phone'] ?? 
                    data['phoneNumber'] ?? 
                    data['contactPhone'] ?? 
                    data['tel'] ??
                    data['phone_number'] ??
                    data['telephone'] ??
                    data['contact_phone'] ??
                    '',
            'email': data['email'] ?? 
                    data['emailAddress'] ?? 
                    data['contactEmail'] ??
                    data['email_address'] ??
                    data['contact_email'] ??
                    '',
          };
        } else {
          print('⚠️ Response хоосон эсвэл буруу формат. Decoded data type: ${decodedData.runtimeType}');
          return null;
        }
      } else if (response.statusCode == 404) {
        print('❌ 404 - Бүртгэл олдсонгүй');
        return null;
      } else {
        print('❌ ${response.statusCode} алдаа');
        print('Response data: ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ opendatalab.mn DioException: ${e.type}');
      print('Алдааны мэдээлэл: ${e.message}');
      print('Response: ${e.response?.data}');
      print('Status code: ${e.response?.statusCode}');
      
      // CORS алдаа эсэхийг шалгах (web platform дээр)
      final errorMessage = e.message?.toLowerCase() ?? '';
      final errorString = e.toString().toLowerCase();
      final isCorsError = kIsWeb && (
        errorMessage.contains('cors') ||
        errorMessage.contains('access-control-allow-origin') ||
        errorMessage.contains('preflight') ||
        errorMessage.contains('blocked') ||
        errorString.contains('cors') ||
        errorString.contains('access-control') ||
        errorString.contains('xmlhttprequest') ||
        (e.type == DioExceptionType.unknown && errorMessage.contains('blocked')) ||
        (e.type == DioExceptionType.connectionError && errorMessage.isEmpty) // Web дээр connectionError заримдаа CORS байж болно
      );
      
      if (isCorsError) {
        print('❌ opendatalab.mn CORS алдаа: Web platform дээр CORS policy-ийн улмаас API хандалт хязгаарлагдсан');
        return {
          'error': 'cors', 
          'message': 'Web platform дээр opendatalab.mn API-д шууд хандах боломжгүй (CORS policy). "opendatalab.mn" товч дараад вэбсайтаас мэдээлэл хайж болно, эсвэл гараар мэдээлэл оруулж болно.'
        };
      }
      
      // Dio алдаа гарвал network алдааны мэдээлэл буцаах
      if (e.type == DioExceptionType.connectionTimeout || 
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        print('❌ opendatalab.mn network алдаа: ${e.message}');
        return {'error': 'network', 'message': 'Интернэт холболт салсан эсвэл network алдаа гарлаа. Интернэт холболтоо шалгаад дахин оролдоно уу. Гараар мэдээлэл оруулж болно.'};
      } else if (e.type == DioExceptionType.badResponse) {
        final statusCode = e.response?.statusCode;
        print('❌ opendatalab.mn response алдаа: $statusCode');
        
        if (statusCode == 404) {
          // 404 алдаа - бүртгэл олдсонгүй
          return {'error': 'not_found', 'message': 'Бүртгэлийн дугаар олдсонгүй. Бүртгэлийн дугаарыг шалгаад дахин оролдоно уу. Гараар мэдээлэл оруулж болно.'};
        } else {
          return {'error': 'api', 'message': 'API-аас алдаа гарлаа (Status: $statusCode). Гараар мэдээлэл оруулж болно.'};
        }
      } else {
        print('❌ opendatalab.mn Dio алдаа: ${e.type} - ${e.message}');
        // Web platform дээр unknown алдаа CORS байж болно
        if (kIsWeb && e.type == DioExceptionType.unknown) {
          return {
            'error': 'cors', 
            'message': 'Web platform дээр opendatalab.mn API-д шууд хандах боломжгүй (CORS policy). "opendatalab.mn" товч дараад вэбсайтаас мэдээлэл хайж болно, эсвэл гараар мэдээлэл оруулж болно.'
          };
        }
        return {'error': 'unknown', 'message': 'Алдаа гарлаа. Гараар мэдээлэл оруулж болно.'};
      }
    } catch (e) {
      print('❌ opendatalab.mn алдаа: $e');
      // Web platform дээр CORS алдаа байж болно
      final errorString = e.toString().toLowerCase();
      if (kIsWeb && (errorString.contains('cors') || errorString.contains('access-control') || errorString.contains('blocked'))) {
        return {
          'error': 'cors', 
          'message': 'Web platform дээр opendatalab.mn API-д шууд хандах боломжгүй (CORS policy). "opendatalab.mn" товч дараад вэбсайтаас мэдээлэл хайж болно, эсвэл гараар мэдээлэл оруулж болно.'
        };
      }
      return {'error': 'unknown', 'message': 'Алдаа гарлаа. Гараар мэдээлэл оруулж болно.'};
    }
  }
}


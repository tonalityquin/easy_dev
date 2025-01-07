import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'states/page_state.dart';
import 'states/plate_state.dart';
import 'states/page_info.dart'; // PageInfo import
import 'screens/type_page.dart';
import 'screens/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Firebase 초기화
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PageState(pages: defaultPages), // pages 전달
        ),
        ChangeNotifierProvider(create: (_) => PlateState()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'easyvalet',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginPage(),
          '/home': (context) => const TypePage(),
        },
      ),
    );
  }
}

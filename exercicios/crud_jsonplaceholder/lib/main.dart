import 'package:flutter/material.dart';
import 'package:crud_jsonplaceholder/screens/posts_screen.dart';
import 'package:crud_jsonplaceholder/services/post_service.dart';

void main() => runApp(const CrudApp());

class CrudApp extends StatelessWidget {
  /// [service] pode ser trocado nos testes.
  final PostService? service;

  const CrudApp({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRUD JSONPlaceholder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: PostsScreen(service: service ?? PostService()),
    );
  }
}

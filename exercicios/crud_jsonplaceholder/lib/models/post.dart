/// Um post da JSONPlaceholder: { "userId": 1, "id": 1, "title": "...", "body": "..." }.
class Post {
  final int? id; // null enquanto o post ainda não foi criado
  final int userId;
  final String title;
  final String body;

  const Post({this.id, required this.userId, required this.title, required this.body});

  /// JSON (Map) vindo da API -> objeto Post.
  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: (json['id'] as num?)?.toInt(),
      userId: (json['userId'] as num?)?.toInt() ?? 1,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
    );
  }

  /// Objeto Post -> JSON (Map) para enviar à API.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'userId': userId,
        'title': title,
        'body': body,
      };

  Post copyWith({int? id, int? userId, String? title, String? body}) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
    );
  }
}

/// Comentário de um post (GET /posts/{id}/comments).
class Comentario {
  final int id;
  final int postId;
  final String name;
  final String email;
  final String body;

  const Comentario({
    required this.id,
    required this.postId,
    required this.name,
    required this.email,
    required this.body,
  });

  factory Comentario.fromJson(Map<String, dynamic> json) {
    return Comentario(
      id: (json['id'] as num?)?.toInt() ?? 0,
      postId: (json['postId'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
    );
  }
}

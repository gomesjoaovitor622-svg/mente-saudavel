# CRUD Flutter com a API pública JSONPlaceholder

CRUD completo de **posts** consumindo <https://jsonplaceholder.typicode.com>.

| Letra | Operação | HTTP | Onde está no código |
|---|---|---|---|
| **C**reate | criar post | `POST /posts` | `PostService.criar` · `post_form_screen.dart` |
| **R**ead | listar / ver / comentários | `GET /posts`, `GET /posts/{id}`, `GET /posts/{id}/comments` | `PostService.listar/buscar/comentarios` · `posts_screen.dart`, `post_detail_screen.dart` |
| **U**pdate | editar post | `PUT /posts/{id}` | `PostService.atualizar` · `post_form_screen.dart` |
| **D**elete | excluir post | `DELETE /posts/{id}` | `PostService.excluir` · `posts_screen.dart` |

## Como rodar
```bash
cd exercicios/crud_jsonplaceholder
flutter create --platforms=android,web,windows .   # 1ª vez: gera as pastas de plataforma
flutter pub get
flutter run            # ou: flutter run -d chrome
flutter test           # 14 testes (serviço HTTP + telas), sem internet
```

## ⚠ A JSONPlaceholder não grava nada
É uma API de **teste**: `POST`, `PUT` e `DELETE` respondem com sucesso, mas **nada é salvo no servidor**
(se você recarregar, os 100 posts originais voltam). Por isso o app mantém a lista **em memória** e a
atualiza depois de cada operação, para o CRUD funcionar visualmente. Detalhes que isso gera:
- `POST` devolve sempre `id = 101`; o app gera o próximo id livre localmente para não repetir.
- Posts criados por você (id fora de 1–100) não existem na API, então o detalhe mostra só os dados locais.

## Estrutura
```
lib/
  main.dart                      # MaterialApp
  models/post.dart               # Post e Comentario (fromJson/toJson)
  services/post_service.dart     # TODAS as chamadas HTTP (package:http) + tratamento de erros
  screens/posts_screen.dart      # lista, busca, menu Editar/Excluir, FAB "Novo post"
  screens/post_form_screen.dart  # formulário (criar e editar) com validação
  screens/post_detail_screen.dart# detalhe + comentários
test/                            # MockClient: testa o CRUD sem acessar a internet
```

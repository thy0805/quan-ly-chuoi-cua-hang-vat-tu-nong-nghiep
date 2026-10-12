import '../core/numbers.dart';

class Session {
  const Session({required this.token, required this.expiresAt, this.branchId});

  final String token;
  final DateTime expiresAt;
  final String? branchId;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    branchId: json['branch_id'] as String?,
  );

  Session inBranch(String? id) =>
      Session(token: token, expiresAt: expiresAt, branchId: id);

  Map<String, dynamic> toJson() => {
    'token': token,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'branch_id': branchId,
  };
}

class Branch {
  const Branch({
    required this.id,
    required this.chainId,
    required this.code,
    required this.name,
  });

  final String id;
  final String chainId;
  final String code;
  final String name;

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
    id: jsonId(json['id']),
    chainId: jsonId(json['chain_id']),
    code: json['code'] as String,
    name: json['name'] as String,
  );
}

class Profile {
  const Profile({
    required this.userId,
    required this.username,
    required this.branches,
    required this.chains,
  });

  final String userId;
  final String username;
  final List<Branch> branches;
  final Map<String, String> chains;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    userId: jsonId((json['user'] as Map<String, dynamic>)['id']),
    username: (json['user'] as Map<String, dynamic>)['username'] as String,
    branches: (json['branches'] as List)
        .map((value) => Branch.fromJson(value as Map<String, dynamic>))
        .toList(),
    chains: {
      for (final value in json['chains'] as List)
        jsonId(value['id']): value['name'] as String,
    },
  );
}

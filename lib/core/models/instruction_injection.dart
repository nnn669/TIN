class InstructionInjection {
  final String id;
  final String title;
  final String prompt;

  const InstructionInjection({
    required this.id,
    required this.title,
    required this.prompt,
  });

  InstructionInjection copyWith({
    String? id,
    String? title,
    String? prompt,
  }) {
    return InstructionInjection(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
      };

  static InstructionInjection fromJson(Map<String, dynamic> json) => InstructionInjection(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        prompt: (json['prompt'] as String?) ?? '',
      );
}


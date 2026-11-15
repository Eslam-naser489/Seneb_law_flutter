import 'package:flutter/material.dart';

import '../../lawyers/domain/office_models.dart';

class WorkspaceLoad<T> extends StatelessWidget {
  const WorkspaceLoad({
    super.key,
    required this.future,
    required this.retry,
    required this.buildData,
  });
  final Future<T> future;
  final VoidCallback retry;
  final Widget Function(T) buildData;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final error = snapshot.error;
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is OfficeFailure ? error.message : 'تعذر تحميل البيانات.',
              ),
              TextButton(onPressed: retry, child: const Text('إعادة المحاولة')),
            ],
          ),
        );
      }
      return buildData(snapshot.data as T);
    },
  );
}

String? workspaceError(Object error) => switch (error) {
  OfficeFailure() => error.message,
  FormatException() => error.message.toString(),
  _ => null,
};

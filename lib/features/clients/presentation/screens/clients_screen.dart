
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubit/clients_cubit.dart';
import '../cubit/clients_state.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  @override
  void initState() {
    super.initState();

    // جلب البيانات أول ما الشاشة تفتح
    context.read<ClientsCubit>().loadClients();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الموكلين'),
      ),
      body: BlocBuilder<ClientsCubit, ClientsState>(
        builder: (context, state) {
          if (state is ClientsLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (state is ClientsError) {
            return Center(
              child: Text('حدث خطأ: ${state.message}'),
            );
          } else if (state is ClientsLoaded) {
            if (state.clients.isEmpty) {
              return const Center(
                child: Text('لا يوجد موكلين نشطين حالياً.'),
              );
            }

            return ListView.builder(
              itemCount: state.clients.length,
              itemBuilder: (context, index) {
                final client = state.clients[index];

                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(client.name),
                  subtitle: Text(
                    client.phone ?? 'لا يوجد رقم',
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.archive,
                      color: Colors.red,
                    ),
                    tooltip: 'أرشفة الموكل',
                    onPressed: () {
                      context
                          .read<ClientsCubit>()
                          .archiveClient(client.id);
                    },
                  ),
                );
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),

      // الانتقال إلى شاشة إضافة موكل جديد
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.push('/add-client');
        },
        icon: const Icon(Icons.add),
        label: const Text('موكل جديد'),
      ),
    );
  }
}

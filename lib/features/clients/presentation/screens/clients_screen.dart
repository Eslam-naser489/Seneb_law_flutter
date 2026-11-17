import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:seneb_law/app/theme/app_colors.dart';
import 'package:seneb_law/app/theme/app_widgets.dart';
import 'package:seneb_law/core/database/app_repository.dart';

import '../cubit/clients_cubit.dart';
import '../cubit/clients_state.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ClientsCubit>().loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final workspace = repo is ScopedAppRepository ? repo : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('إدارة الموكلين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Column(
        children: [
          // Professional Search Bar Container
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم الموكل أو رقم الهاتف...',
                      hintStyle: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: AppColors.secondaryText),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20, color: AppColors.secondaryText),
                              onPressed: () {
                                _searchController.clear();
                                context.read<ClientsCubit>().searchClients('');
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.5),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      context.read<ClientsCubit>().searchClients(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Clients List
          Expanded(
            child: BlocBuilder<ClientsCubit, ClientsState>(
              builder: (context, state) {
                if (state is ClientsLoading) {
                  return const AppLoadingIndicator(message: 'جارٍ تحميل الموكلين...');
                } else if (state is ClientsError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text('حدث خطأ: ${state.message}'),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => context.read<ClientsCubit>().loadClients(),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                } else if (state is ClientsLoaded) {
                  if (state.clients.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: AppEmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'لا يوجد موكلين مطابقين للبحث',
                          subtitle: _searchController.text.isNotEmpty
                              ? 'جرّب البحث بكلمات أخرى أو تحقق من كتابة الاسم.'
                              : 'ابدأ بإضافة أول موكل إلى قاعدة البيانات.',
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: state.clients.length,
                    itemBuilder: (context, index) {
                      final client = state.clients[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          onTap: workspace == null
                              ? null
                              : () async {
                                  await context.push(
                                    '/client/${Uri.encodeComponent(client.id)}',
                                  );
                                  if (context.mounted) {
                                    context.read<ClientsCubit>().loadClients();
                                  }
                                },
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.primaryNavy.withValues(alpha: 0.08),
                            child: Text(
                              client.name.isNotEmpty ? client.name.characters.first : 'م',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryNavy,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          title: Text(
                            client.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primaryText,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.phone_outlined, size: 14, color: AppColors.secondaryText),
                                const SizedBox(width: 4),
                                Text(
                                  client.phone != null && client.phone!.trim().isNotEmpty
                                      ? client.phone!
                                      : 'لا يوجد هاتف مسجل',
                                  textDirection: client.phone != null ? TextDirection.ltr : null,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: workspace != null
                              ? const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.secondaryText)
                              : IconButton(
                                  icon: const Icon(
                                    Icons.archive_outlined,
                                    color: AppColors.error,
                                  ),
                                  tooltip: 'أرشفة الموكل',
                                  onPressed: () {
                                    context.read<ClientsCubit>().archiveClient(client.id);
                                  },
                                ),
                        ),
                      );
                    },
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),

      floatingActionButton: workspace?.canEdit == false
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/add-client'),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('موكل جديد', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
    );
  }
}

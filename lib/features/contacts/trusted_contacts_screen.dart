import 'package:flutter/material.dart';
import '../../services/contacts_service.dart';
import '../../widgets/branding.dart';

class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final _svc = ContactsService();
  List<ContactEntry> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _svc.getContacts();
    setState(() {
      _contacts = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final res = await showDialog<ContactEntry>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    );
    if (res != null) {
      await _svc.addContact(res);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Contacts')),
      body: PastelBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _contacts.length >= 5 ? null : _add,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_contacts.length >= 5 ? 'Max 5' : 'Add'),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _contacts.isEmpty
                          ? const Center(child: Text('No contacts yet. Add someone you trust.'))
                          : ListView.separated(
                              itemCount: _contacts.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final c = _contacts[i];
                                return GlassCard(
                                  padding: const EdgeInsets.all(16),
                                  child: ListTile(
                                    leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                                    title: Text(c.name),
                                    subtitle: Text('${c.relationship ?? 'Contact'} • ${c.phone}${c.email != null ? ' • ${c.email}' : ''}'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      onPressed: () async {
                                        await _svc.removeAt(i);
                                        await _load();
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();
  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _rel = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Trusted Contact'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email (optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _rel, decoration: const InputDecoration(labelText: 'Relationship (optional)')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (_formKey.currentState!.validate()) Navigator.of(context).pop(ContactEntry(name: _name.text.trim(), phone: _phone.text.trim(), email: _email.text.trim().isEmpty? null: _email.text.trim(), relationship: _rel.text.trim().isEmpty? null: _rel.text.trim())); }, child: const Text('Save')),
      ],
    );
  }
}
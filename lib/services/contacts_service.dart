import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ContactEntry {
  final String name;
  final String phone;
  final String? email;
  final String? relationship;
  ContactEntry({required this.name, required this.phone, this.email, this.relationship});

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'relationship': relationship,
      };

  static ContactEntry fromJson(Map<String, dynamic> j) => ContactEntry(
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        email: j['email'] as String?,
        relationship: j['relationship'] as String?,
      );
}

class ContactsService {
  static const _key = 'trusted_contacts_v1';

  Future<List<ContactEntry>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(ContactEntry.fromJson).toList();
  }

  Future<void> saveContacts(List<ContactEntry> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> addContact(ContactEntry c) async {
    final list = await getContacts();
    list.add(c);
    await saveContacts(list);
  }

  Future<void> removeAt(int index) async {
    final list = await getContacts();
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await saveContacts(list);
  }
}
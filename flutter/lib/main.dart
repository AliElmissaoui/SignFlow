import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiBase = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000/api');
const storage = FlutterSecureStorage();
const navy = Color(0xFF111C35);
const indigo = Color(0xFF5758E8);
const pale = Color(0xFFF6F7FB);

void main() => runApp(const SignFlowApp());

class Api {
  String? token;
  Future<dynamic> call(String method, String path, [Map<String, dynamic>? data]) async {
    final uri = Uri.parse('$apiBase$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final response = method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(data ?? {}));
    dynamic body;
    try { body = jsonDecode(response.body); } catch (_) { throw Exception('Erreur HTTP ${response.statusCode}'); }
    if (response.statusCode >= 400) {
      final message = body is Map ? (body['message'] ?? body['errors']?.toString()) : null;
      throw Exception(message ?? 'Erreur HTTP ${response.statusCode}');
    }
    return body;
  }
}
final api = Api();

class SignFlowApp extends StatelessWidget {
  const SignFlowApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SignFlow',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: pale,
      colorScheme: ColorScheme.fromSeed(seedColor: indigo),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE3E6EF))),
      ),
    ),
    home: const Workspace(),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  bool loading = true, busy = false, registering = false;
  String? error, name;
  final email = TextEditingController(), password = TextEditingController(), person = TextEditingController(), companyName = TextEditingController(), inviteCode = TextEditingController();
  List<dynamic> companies = [], members = [], documents = [], invitations = [];
  int? companyId;
  int tab = 0;
  String get companyLabel {
    for (final c in companies) { if (c['id'] == companyId) return c['name'].toString(); }
    return 'Mon espace';
  }
  String get role {
    for (final c in companies) { if (c['id'] == companyId) return (c['pivot']?['role'] ?? '').toString(); }
    return '';
  }
  bool get canManage => role == 'owner' || role == 'admin';
  @override void initState() { super.initState(); restore(); }
  @override void dispose() { email.dispose(); password.dispose(); person.dispose(); companyName.dispose(); inviteCode.dispose(); super.dispose(); }

  Future<void> restore() async {
    api.token = await storage.read(key: 'token');
    if (api.token != null) {
      try { await refresh(); } catch (_) { api.token = null; await storage.delete(key: 'token'); }
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> refresh() async {
    companies = await api.call('GET', '/companies');
    if (companies.isNotEmpty) {
      if (!companies.any((c) => c['id'] == companyId)) companyId = companies.first['id'];
      await loadCompany();
    }
    if (mounted) setState(() {});
  }
  Future<void> loadCompany() async {
    if (companyId == null) return;
    members = await api.call('GET', '/companies/$companyId/team');
    documents = await api.call('GET', '/companies/$companyId/documents');
    invitations = [];
    try { invitations = await api.call('GET', '/companies/$companyId/invitations'); } catch (_) { /* Non-admin or API V0.2 */ }
    if (mounted) setState(() {});
  }
  Future<void> run(Future<void> Function() fn) async {
    if (mounted) setState(() { busy = true; error = null; });
    try { await fn(); } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> authenticate() => run(() async {
    final invited = registering && inviteCode.text.trim().isNotEmpty;
    final result = await api.call('POST', invited ? '/invitations/${inviteCode.text.trim()}/register' : (registering ? '/register' : '/login'), registering
        ? {'name': person.text.trim(), if (!invited) 'company': companyName.text.trim(), 'email': email.text.trim(), 'password': password.text}
        : {'email': email.text.trim(), 'password': password.text});
    api.token = result['token'];
    name = result['user']['name'];
    await storage.write(key: 'token', value: api.token);
    await refresh();
  });
  Future<void> logout() async {
    try { await api.call('POST', '/logout'); } catch (_) {}
    await storage.delete(key: 'token');
    if (mounted) setState(() { api.token = null; companyId = null; companies = []; members = []; documents = []; invitations = []; });
  }
  Future<void> invite() async {
    final input = TextEditingController();
    String selectedRole = 'signer';
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Inviter un collaborateur'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Un lien d’invitation sécurisé sera créé, valable 7 jours.'),
        const SizedBox(height: 20),
        TextField(controller: input, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Adresse email', prefixIcon: Icon(Icons.alternate_email))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(value: selectedRole, decoration: const InputDecoration(labelText: 'Rôle'),
          items: const [DropdownMenuItem(value: 'admin', child: Text('Administrateur')), DropdownMenuItem(value: 'manager', child: Text('Manager')), DropdownMenuItem(value: 'signer', child: Text('Signataire')), DropdownMenuItem(value: 'viewer', child: Text('Lecteur'))],
          onChanged: (v) => update(() => selectedRole = v ?? 'signer')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          if (!input.text.contains('@')) return;
          Navigator.pop(ctx);
          await run(() async {
            final result = await api.call('POST', '/companies/$companyId/team', {'email': input.text.trim(), 'role': selectedRole});
            await loadCompany();
            if (!mounted) return;
            final token = result['token'].toString();
            await showDialog(context: context, builder: (dialog) => AlertDialog(
              title: const Text('Invitation créée'),
              content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mark_email_read_outlined, color: indigo, size: 54),
                const SizedBox(height: 12),
                const Text('Copiez ce code et transmettez-le au destinataire. Aucun email automatique n’est envoyé dans cette version.'),
                const SizedBox(height: 12),
                SelectableText(token, style: const TextStyle(fontSize: 12)),
              ])),
              actions: [TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: token)); }, child: const Text('Copier le code')),
                FilledButton(onPressed: () => Navigator.pop(dialog), child: const Text('Terminer'))],
            ));
          });
        }, child: const Text('Créer l’invitation'))],
    )));
    input.dispose();
  }
  Future<void> acceptInvitation() async {
    final input = TextEditingController();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Rejoindre une entreprise'),
      content: SizedBox(width: 420, child: TextField(controller: input, decoration: const InputDecoration(labelText: 'Code d’invitation'))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () { final token = input.text.trim(); Navigator.pop(ctx); run(() async { await api.call('POST', '/invitations/$token/accept'); await refresh(); }); }, child: const Text('Accepter'))],
    ));
    input.dispose();
  }
  Future<void> createDocument() async {
    final input = TextEditingController();
    final selected = <int>[];
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: const Text('Nouveau workflow'),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: input, decoration: const InputDecoration(labelText: 'Titre du document')),
        const SizedBox(height: 18), const Text('Sélectionnez les signataires dans l’ordre souhaité'),
        ...members.map((m) => CheckboxListTile(
          value: selected.contains(m['id']), title: Text(m['name'].toString()), subtitle: Text(m['email'].toString()),
          onChanged: (v) => update(() { if (v == true) { selected.add(m['id']); } else { selected.remove(m['id']); } }),
        )),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: selected.isEmpty ? null : () { Navigator.pop(ctx); run(() async { await api.call('POST', '/companies/$companyId/documents', {'title': input.text.trim(), 'signer_ids': selected}); await loadCompany(); }); }, child: const Text('Créer'))],
    )));
    input.dispose();
  }

  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (api.token == null) return _authScreen();
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      drawer: wide ? null : Drawer(child: SafeArea(child: _navigation())),
      body: Row(children: [
        if (wide) SizedBox(width: 245, child: _navigation()),
        Expanded(child: Column(children: [
          Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15), child: Row(children: [
            if (!wide) Builder(builder: (ctx) => IconButton(onPressed: () => Scaffold.of(ctx).openDrawer(), icon: const Icon(Icons.menu))),
            Expanded(child: Text(companyLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: navy))),
            if (companies.isNotEmpty) DropdownButton<int>(value: companyId, underline: const SizedBox(), items: companies.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['name'].toString()))).toList(), onChanged: (id) => run(() async { companyId = id; await loadCompany(); })),
            const SizedBox(width: 12), CircleAvatar(backgroundColor: const Color(0xFFEDEAFF), child: Text((name ?? 'U').substring(0, 1).toUpperCase(), style: const TextStyle(color: indigo, fontWeight: FontWeight.bold))),
          ])),
          Expanded(child: ListView(padding: EdgeInsets.all(wide ? 30 : 16), children: [
            if (error != null) Card(color: const Color(0xFFFFF1F1), child: Padding(padding: const EdgeInsets.all(14), child: Text(error!, style: const TextStyle(color: Color(0xFFB3261E))))),
            Text(tab == 0 ? 'Vue d’ensemble' : tab == 1 ? 'Gestion de l’équipe' : 'Documents & workflows', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: navy)),
            const SizedBox(height: 6), Text('Bienvenue dans votre espace SignFlow · $companyLabel', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            if (tab == 0) _overview(),
            if (tab == 1) _team(),
            if (tab == 2) _documents(),
            if (busy) const Padding(padding: EdgeInsets.only(top: 18), child: LinearProgressIndicator()),
            const SizedBox(height: 32),
            const Text('SignFlow V0.3 · Workflow de validation prototype, sans signature PDF ni envoi email automatique.', style: TextStyle(fontSize: 12, color: Colors.black45)),
          ])),
        ])),
      ]),
    );
  }
  Widget _authScreen() => Scaffold(body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 460), child: Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(30), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.draw_rounded, size: 48, color: indigo),
        const SizedBox(height: 12), const Text('SignFlow', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: navy)),
        const SizedBox(height: 8), Text(registering ? 'Créez votre espace entreprise' : 'Connectez-vous à votre espace', textAlign: TextAlign.center),
        const SizedBox(height: 25),
        if (registering) ...[
          TextField(controller: person, decoration: const InputDecoration(labelText: 'Votre nom')),
          const SizedBox(height: 12), TextField(controller: companyName, decoration: const InputDecoration(labelText: 'Nom de l’entreprise (sans invitation)')),
          const SizedBox(height: 12),
          TextField(controller: inviteCode, decoration: const InputDecoration(labelText: 'Code d’invitation (facultatif)')),
          const SizedBox(height: 12),
        ],
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 12), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (10 caractères minimum)')),
        const SizedBox(height: 18), FilledButton(onPressed: busy ? null : authenticate, child: Padding(padding: const EdgeInsets.all(12), child: Text(registering ? 'Créer mon entreprise' : 'Se connecter'))),
        TextButton(onPressed: () => setState(() => registering = !registering), child: Text(registering ? 'Déjà inscrit ? Connexion' : 'Créer une entreprise')),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      ])),
    ),
  ))));
  Widget _navigation() => Container(color: navy, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Padding(padding: EdgeInsets.fromLTRB(24, 32, 20, 32), child: Row(children: [Icon(Icons.draw_rounded, color: Colors.white, size: 28), SizedBox(width: 12), Text('SignFlow', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800))])),
    _nav(0, Icons.grid_view_rounded, 'Tableau de bord'),
    _nav(2, Icons.description_outlined, 'Documents'),
    _nav(1, Icons.groups_2_outlined, 'Équipe & accès'),
    const Spacer(),
    Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(onPressed: logout, icon: const Icon(Icons.logout, color: Colors.white70), label: const Text('Déconnexion', style: TextStyle(color: Colors.white70)))),
  ]));
  Widget _nav(int index, IconData icon, String label) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Material(
    color: tab == index ? const Color(0xFF323D69) : Colors.transparent, borderRadius: BorderRadius.circular(12),
    child: ListTile(leading: Icon(icon, color: tab == index ? Colors.white : Colors.white60), title: Text(label, style: TextStyle(color: tab == index ? Colors.white : Colors.white60, fontWeight: FontWeight.w600)),
      onTap: () { setState(() => tab = index); if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.maybePop(context); }),
  ));
  Widget _stat(IconData icon, String title, String value, Color tint) => Container(
    padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
    child: Row(children: [CircleAvatar(radius: 25, backgroundColor: tint.withOpacity(.12), child: Icon(icon, color: tint)), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.black54)), Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: navy))])]),
  );
  Widget _overview() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    LayoutBuilder(builder: (ctx, size) => Wrap(spacing: 14, runSpacing: 14, children: [
      SizedBox(width: size.maxWidth > 750 ? (size.maxWidth - 28) / 3 : size.maxWidth, child: _stat(Icons.description_outlined, 'Documents', '${documents.length}', indigo)),
      SizedBox(width: size.maxWidth > 750 ? (size.maxWidth - 28) / 3 : size.maxWidth, child: _stat(Icons.people_outline, 'Collaborateurs', '${members.length}', const Color(0xFF0B9F85))),
      SizedBox(width: size.maxWidth > 750 ? (size.maxWidth - 28) / 3 : size.maxWidth, child: _stat(Icons.hourglass_top, 'En cours', '${documents.where((d) => d['status'] == 'progress').length}', const Color(0xFFE99A37))),
    ])),
    const SizedBox(height: 26),
    Container(width: double.infinity, padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(20)), child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 14, children: [
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Votre équipe, vos validations.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.white)), SizedBox(height: 8), Text('Invitez vos collaborateurs et organisez vos workflows.', style: TextStyle(color: Colors.white70))]),
      FilledButton.icon(onPressed: canManage ? invite : null, icon: const Icon(Icons.person_add_alt_1), label: const Text('Inviter un membre')),
    ])),
    const SizedBox(height: 24),
    const Text('Activité récente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
    const SizedBox(height: 12), ...documents.take(5).map(_documentTile),
    if (documents.isEmpty) _empty(Icons.description_outlined, 'Aucun document pour le moment', 'Créez votre premier workflow depuis Documents.'),
  ]);
  Widget _team() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Wrap(spacing: 12, runSpacing: 12, children: [
      if (canManage) FilledButton.icon(onPressed: invite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Inviter un membre')),
      OutlinedButton.icon(onPressed: acceptInvitation, icon: const Icon(Icons.mark_email_read_outlined), label: const Text('Accepter une invitation')),
    ]),
    const SizedBox(height: 22),
    Text('Membres actifs (${members.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
    const SizedBox(height: 12),
    ...members.map((m) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Row(children: [
      CircleAvatar(backgroundColor: const Color(0xFFECEBFF), child: Text((m['name'] as String).substring(0, 1).toUpperCase(), style: const TextStyle(color: indigo, fontWeight: FontWeight.bold))),
      const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)), Text(m['email'].toString(), style: const TextStyle(fontSize: 12, color: Colors.black54))])),
      _chip((m['pivot']?['role'] ?? 'membre').toString()),
    ]))),
    if (canManage) ...[
      const SizedBox(height: 22),
      Text('Invitations en attente (${invitations.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 12),
      ...invitations.map((i) => ListTile(tileColor: Colors.white, leading: const Icon(Icons.outgoing_mail, color: indigo), title: Text(i['email'].toString()), subtitle: Text('Rôle : ${i['role']} · Expire : ${i['expires_at']}'), trailing: const Icon(Icons.schedule))),
      if (invitations.isEmpty) _empty(Icons.mark_email_read_outlined, 'Aucune invitation en attente', 'Invitez un collaborateur pour commencer.'),
    ],
  ]);
  Widget _documents() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: createDocument, icon: const Icon(Icons.add), label: const Text('Nouveau workflow'))),
    const SizedBox(height: 18), ...documents.map(_documentTile),
    if (documents.isEmpty) _empty(Icons.description_outlined, 'Aucun document', 'Les workflows créés apparaîtront ici.'),
  ]);
  Widget _documentTile(dynamic d) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Icon(Icons.insert_drive_file_outlined, color: indigo), const SizedBox(width: 12), Expanded(child: Text(d['title'].toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), _chip(d['status'].toString())]),
    const SizedBox(height: 10), Text('${(d['steps'] as List).length} étape(s) de validation', style: const TextStyle(color: Colors.black54)),
    const SizedBox(height: 10), Wrap(spacing: 10, children: [
      if (d['status'] == 'draft') OutlinedButton(onPressed: () => run(() async { await api.call('POST', '/companies/$companyId/documents/${d['id']}/start'); await loadCompany(); }), child: const Text('Démarrer')),
      if (d['status'] == 'progress') FilledButton.tonal(onPressed: () => run(() async { await api.call('POST', '/companies/$companyId/documents/${d['id']}/sign'); await loadCompany(); }), child: const Text('Valider mon étape')),
    ]),
  ]));
  Widget _chip(String value) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF0F0FF), borderRadius: BorderRadius.circular(30)), child: Text(value, style: const TextStyle(color: indigo, fontSize: 12, fontWeight: FontWeight.w700)));
  Widget _empty(IconData icon, String title, String subtitle) => Container(width: double.infinity, padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(icon, color: indigo, size: 36), const SizedBox(height: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54))]));
}

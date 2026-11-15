import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dashboard.dart';
import 'source.dart';
import 'telemetry.dart';
import 'visuals.dart';

void main() => runApp(const ProviderScope(child: GrainGuard()));

class GrainGuard extends StatefulWidget {
  const GrainGuard({super.key});

  @override
  State<GrainGuard> createState() => _GrainGuardState();
}

class _GrainGuardState extends State<GrainGuard> {
  late final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const Gate())],
  );

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'GrainGuard',
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: wheat,
            brightness: Brightness.dark,
          ).copyWith(
            primary: wheat,
            onPrimary: ink,
            surface: panel,
            onSurface: paper,
            onSurfaceVariant: muted,
            secondary: lime,
            error: coral,
          ),
      scaffoldBackgroundColor: ink,
      fontFamily: 'Work Sans',
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: Color(0xff584b45),
        height: 69,
      ),
    ),
  );
}

class Gate extends ConsumerWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoProvider);
    if (demo != null) {
      return GrainStart(
        key: const ValueKey('demo-grain'),
        onExit: () => ref.read(demoProvider.notifier).select(null),
        dashboard: (grain, changeGrain) => DemoDashboard(
          key: ValueKey((demo, grain)),
          scenario: demo,
          grain: grain,
          onChangeGrain: changeGrain,
        ),
      );
    }
    return ref
        .watch(cloudProvider)
        .when(
          loading: () => const Welcome(status: 'Connecting to sign-in…'),
          error: (_, _) => Welcome(
            status: 'Sign-in service unavailable. Check your connection.',
            retry: () => ref.invalidate(cloudProvider),
          ),
          data: (cloud) => cloud == null
              ? const Welcome(
                  status: 'Live sign-in requires a configured build.',
                )
              : StreamBuilder<User?>(
                  stream: cloud.auth.authStateChanges(),
                  builder: (context, snapshot) {
                    final user = snapshot.data;
                    if (user != null) {
                      return GrainStart(
                        key: ValueKey(user.uid),
                        onExit: cloud.auth.signOut,
                        dashboard: (grain, changeGrain) => Assignments(
                          cloud: cloud,
                          uid: user.uid,
                          grain: grain,
                          onChangeGrain: changeGrain,
                        ),
                      );
                    }
                    return Welcome(
                      cloud: cloud,
                      status: snapshot.hasError
                          ? 'Sign-in session unavailable.'
                          : null,
                    );
                  },
                ),
        );
  }
}

class GrainStart extends StatefulWidget {
  const GrainStart({super.key, required this.onExit, required this.dashboard});

  final VoidCallback onExit;
  final Widget Function(Grain, VoidCallback) dashboard;

  @override
  State<GrainStart> createState() => _GrainStartState();
}

class _GrainStartState extends State<GrainStart> {
  Grain? selection;

  @override
  Widget build(BuildContext context) {
    final grain = selection;
    if (grain != null) {
      return widget.dashboard(grain, () => setState(() => selection = null));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Brand(),
        leading: BackButton(onPressed: widget.onExit),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
              children: [
                Text('Choose your grain', style: display(43)),
                const SizedBox(height: 10),
                const Text(
                  'Choose a grain to see its bins.',
                  style: TextStyle(color: muted, fontSize: 16),
                ),
                const SizedBox(height: 22),
                for (final option in Grain.values) ...[
                  Tile(
                    fill: option.dye,
                    onTap: () => setState(() => selection = option),
                    child: Row(
                      children: [
                        Expanded(child: Text(option.label, style: display(36))),
                        SizedBox(
                          width: 104,
                          child: ExcludeSemantics(
                            child: SackStage(
                              grain: option,
                              interactive: false,
                              height: 112,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Welcome extends ConsumerStatefulWidget {
  const Welcome({super.key, this.cloud, this.status, this.retry});
  final Cloud? cloud;
  final String? status;
  final VoidCallback? retry;

  @override
  ConsumerState<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<Welcome> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool hidden = true;
  bool busy = false;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> authenticate({bool reset = false}) async {
    final auth = widget.cloud!.auth;
    if (!email.text.contains('@') || (!reset && password.text.isEmpty)) {
      setState(
        () => message = reset
            ? 'Enter your email address.'
            : 'Enter your email and password.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (reset) {
        await auth
            .sendPasswordResetEmail(email: email.text.trim())
            .timeout(const Duration(seconds: 15));
        if (mounted) {
          setState(() => message = 'Check your email for reset instructions.');
        }
      } else {
        await auth
            .signInWithEmailAndPassword(
              email: email.text.trim(),
              password: password.text,
            )
            .timeout(const Duration(seconds: 15));
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => message = switch (error.code) {
            'network-request-failed' =>
              'Check your internet connection and try again.',
            'too-many-requests' => 'Wait a moment before trying again.',
            _ =>
              reset
                  ? 'Password reset unavailable. Check the address and try again.'
                  : 'Sign-in failed. Check your invited account details.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'The request timed out. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: Brand()),
                const SizedBox(height: 22),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xff2c2643),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xff514660)),
                  ),
                  child: const SackStage(
                    grain: Grain.wheat,
                    interactive: false,
                  ),
                ),
                const SizedBox(height: 24),
                Text('Your grain bins', style: display(46)),
                const SizedBox(height: 9),
                Text(
                  widget.cloud == null
                      ? 'Explore bin conditions and device readings with the offline demo.'
                      : 'Sign in with your invited account to see assigned bins.',
                  style: const TextStyle(color: muted, fontSize: 16),
                ),
                const SizedBox(height: 20),
                if (widget.cloud != null) ...[
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: hidden,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) {
                      if (!busy) authenticate();
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: hidden ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : authenticate,
                    child: Text(busy ? 'Please wait…' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => authenticate(reset: true),
                    child: const Text('Reset password'),
                  ),
                ],
                if (message != null || widget.status != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        message ?? widget.status!,
                        style: const TextStyle(color: muted),
                      ),
                    ),
                  ),
                if (widget.retry != null)
                  TextButton(
                    onPressed: widget.retry,
                    child: const Text('Retry connection'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.read(demoProvider.notifier).select(Scenario.stable),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Open demo mode'),
                  style: FilledButton.styleFrom(
                    backgroundColor: lime,
                    foregroundColor: ink,
                    minimumSize: const Size.fromHeight(53),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class Assignments extends ConsumerStatefulWidget {
  const Assignments({
    super.key,
    required this.cloud,
    required this.uid,
    required this.grain,
    required this.onChangeGrain,
  });
  final Cloud cloud;
  final String uid;
  final Grain grain;
  final VoidCallback onChangeGrain;
  @override
  ConsumerState<Assignments> createState() => _AssignmentsState();
}

class _AssignmentsState extends ConsumerState<Assignments> {
  String? selected;
  late Stream<Map<String, String>> assignments = widget.cloud.assignments(
    widget.uid,
    widget.grain.name,
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, String>>(
    stream: assignments,
    builder: (context, snapshot) {
      final bins = snapshot.data ?? const <String, String>{};
      if (snapshot.hasError || bins.isEmpty) {
        final waiting =
            !snapshot.hasError &&
            snapshot.connectionState == ConnectionState.waiting;
        return Scaffold(
          appBar: AppBar(
            title: const Brand(),
            leading: BackButton(onPressed: widget.onChangeGrain),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'Assigned bins unavailable'
                        : waiting
                        ? 'Looking for assigned bins…'
                        : 'No ${widget.grain.label.toLowerCase()} bins assigned',
                    style: display(30),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    supportContact.isEmpty
                        ? 'Contact your GrainGuard project administrator.'
                        : supportContact,
                  ),
                  if (snapshot.hasError)
                    TextButton(
                      onPressed: () => setState(() {
                        assignments = widget.cloud.assignments(
                          widget.uid,
                          widget.grain.name,
                        );
                      }),
                      child: const Text('Retry'),
                    ),
                  TextButton(
                    onPressed: () =>
                        ref.read(demoProvider.notifier).select(Scenario.stable),
                    child: const Text('Open demo mode'),
                  ),
                  TextButton(
                    onPressed: widget.cloud.auth.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final active = bins.containsKey(selected)
          ? selected
          : bins.length == 1
          ? bins.keys.single
          : null;
      if (active == null) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Select a bin'),
            leading: BackButton(onPressed: widget.onChangeGrain),
          ),
          body: ListView(
            children: [
              for (final entry in bins.entries)
                ListTile(
                  leading: const Icon(Icons.warehouse_outlined),
                  title: Text(entry.value),
                  subtitle: Text(entry.key),
                  onTap: () => setState(() => selected = entry.key),
                ),
            ],
          ),
        );
      }
      return LiveBin(
        key: ValueKey(active),
        cloud: widget.cloud,
        uid: widget.uid,
        id: active,
        label: bins[active]!,
        grain: widget.grain,
        onChangeGrain: widget.onChangeGrain,
        onSelect: bins.length == 1
            ? null
            : () => setState(() => selected = null),
      );
    },
  );
}

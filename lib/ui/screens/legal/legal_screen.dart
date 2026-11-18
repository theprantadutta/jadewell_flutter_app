import 'dart:async';

import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../state/platform_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../settings/screen_chrome.dart';

/// The developer's contact address (PRIVACY.md §14, TERMS.md, REFUND.md).
const kContactEmail = 'prantadutta1997@gmail.com';

/// The same documents on the web (`legal.pranta.dev/jadewell/<doc>`).
const kLegalWebBase = 'https://legal.pranta.dev/jadewell';

/// The legal documents bundled in `assets/legal/` (identical copies are
/// served at [kLegalWebBase]).
enum LegalDoc {
  privacy('assets/legal/PRIVACY.md'),
  terms('assets/legal/TERMS.md'),
  refund('assets/legal/REFUND.md');

  const LegalDoc(this.asset);
  final String asset;

  String title(AppLocalizations l) => switch (this) {
        LegalDoc.privacy => l.legalPrivacy,
        LegalDoc.terms => l.legalTerms,
        LegalDoc.refund => l.legalRefund,
      };

  /// `privacy` / `terms` / `refund` from a route; unknown names fall back to privacy.
  static LegalDoc fromName(String? name) => LegalDoc.values.asNameMap()[name] ?? LegalDoc.privacy;
}

/// Opens [uri] outside the app (browser, mail app). When nothing can handle
/// it, copies the address instead and says so.
Future<void> openExternalLink(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    opened = false;
  }
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: uri.scheme == 'mailto' ? uri.path : uri.toString()));
  if (context.mounted) showJwToast(context, AppLocalizations.of(context).commonLinkCopied);
}

/// Reads a bundled legal document offline, in the Clay Pop page frame.
class LegalScreen extends ConsumerStatefulWidget {
  const LegalScreen({super.key, required this.doc, this.bundle});

  final LegalDoc doc;

  /// Defaults to [rootBundle]; tests may pass their own.
  final AssetBundle? bundle;

  @override
  ConsumerState<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends ConsumerState<LegalScreen> {
  late Future<String> _source = _load();

  Future<String> _load() => (widget.bundle ?? rootBundle).loadString(widget.doc.asset);

  @override
  void didUpdateWidget(LegalScreen old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) _source = _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final haptic = ref.watch(hapticsProvider).selection;
    return JwPage(
      title: widget.doc.title(l),
      onHaptic: haptic,
      child: FutureBuilder<String>(
        future: _source,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.legalLoadFailed, textAlign: TextAlign.center, style: jw.text.body.copyWith(color: jw.textMuted)),
              ),
            );
          }
          if (!snap.hasData) return const SizedBox.shrink();
          return SelectionArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 22, 16, 28 + MediaQuery.paddingOf(context).bottom),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: DecoratedBox(
                      decoration: jw.clay(ClayLevel.raised, radius: 26),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                        child: LegalMarkdown(source: snap.data!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---- a small markdown renderer for our own legal files ----

/// One block of a legal document.
sealed class LegalBlock {
  const LegalBlock();
}

class LegalHeading extends LegalBlock {
  const LegalHeading(this.level, this.text);
  final int level;
  final String text;
}

class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.text);
  final String text;
}

class LegalBullet extends LegalBlock {
  const LegalBullet(this.text);
  final String text;
}

/// A pipe table: [header] cells, then [rows] of cells.
class LegalTable extends LegalBlock {
  const LegalTable(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

/// Parses the subset of markdown the legal documents use: `#`/`##`/`###`
/// headings, paragraphs (two trailing spaces = line break), `- ` bullets and
/// pipe tables. Inline markup is handled when rendering.
abstract final class LegalMarkdownParser {
  static final _separatorCell = RegExp(r'^:?-+:?$');

  static List<LegalBlock> parse(String source) {
    final out = <LegalBlock>[];
    final lines = source.replaceAll('\r', '').split('\n');
    final paragraph = StringBuffer();

    void flush() {
      final text = paragraph.toString().trim();
      if (text.isNotEmpty) out.add(LegalParagraph(text));
      paragraph.clear();
    }

    List<String> cells(String line) {
      final parts = line.trim().split('|').map((c) => c.trim()).toList();
      if (parts.isNotEmpty && parts.first.isEmpty) parts.removeAt(0);
      if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
      return parts;
    }

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();
      if (line.isEmpty) {
        flush();
      } else if (line.startsWith('#')) {
        flush();
        final level = line.indexOf(' ');
        if (level > 0 && level <= 3 && line.substring(0, level).split('').every((c) => c == '#')) {
          out.add(LegalHeading(level, line.substring(level + 1).trim()));
        } else {
          paragraph.write('$line ');
        }
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        flush();
        out.add(LegalBullet(line.substring(2).trim()));
      } else if (line.startsWith('|')) {
        flush();
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final c = cells(lines[i]);
          if (!c.every(_separatorCell.hasMatch)) rows.add(c);
          i++;
        }
        i--;
        if (rows.isNotEmpty) out.add(LegalTable(rows.first, rows.skip(1).toList()));
      } else {
        paragraph.write(raw.endsWith('  ') ? '$line\n' : '$line ');
      }
    }
    flush();
    return out;
  }
}

/// Renders [source] (see [LegalMarkdownParser]) with `**bold**`, `` `code` ``,
/// and tappable bare URLs and email addresses.
class LegalMarkdown extends StatefulWidget {
  const LegalMarkdown({super.key, required this.source});

  final String source;

  @override
  State<LegalMarkdown> createState() => _LegalMarkdownState();
}

class _LegalMarkdownState extends State<LegalMarkdown> {
  late List<LegalBlock> _blocks = LegalMarkdownParser.parse(widget.source);
  final List<TapGestureRecognizer> _recognizers = [];

  static final _inline = RegExp(
    r'\*\*(.+?)\*\*' // bold
    r'|`([^`]+)`' // code
    r'|(https?://[^\s<>()]+)' // bare URL
    r'|([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})', // email
  );

  @override
  void didUpdateWidget(LegalMarkdown old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _blocks = LegalMarkdownParser.parse(widget.source);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _link(String label, Uri uri, TextStyle style) {
    final r = TapGestureRecognizer()..onTap = () => unawaited(openExternalLink(context, uri));
    _recognizers.add(r);
    return TextSpan(text: label, style: style, recognizer: r, semanticsLabel: label);
  }

  /// Inline spans for [text]; links keep the surrounding weight.
  List<InlineSpan> _spans(String text, TextStyle base, {bool bold = false}) {
    final jw = context.jw;
    final linkStyle = TextStyle(
      color: jw.purpleText,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: jw.purpleText,
    );
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start)));
      if (m.group(1) != null) {
        out.add(TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700),
          children: _spans(m.group(1)!, base, bold: true),
        ));
      } else if (m.group(2) != null) {
        out.add(TextSpan(
          text: m.group(2),
          style: jw.text.numM.copyWith(fontSize: (base.fontSize ?? 16) * 0.92, color: jw.textPrimary),
        ));
      } else if (m.group(3) != null) {
        // A sentence's full stop or comma isn't part of the address.
        var url = m.group(3)!;
        var tail = '';
        while (url.isNotEmpty && '.,;:!?'.contains(url[url.length - 1])) {
          tail = url[url.length - 1] + tail;
          url = url.substring(0, url.length - 1);
        }
        out.add(_link(url, Uri.parse(url), linkStyle));
        if (tail.isNotEmpty) out.add(TextSpan(text: tail));
      } else {
        final email = m.group(4)!;
        out.add(_link(email, Uri(scheme: 'mailto', path: email), linkStyle));
      }
      last = m.end;
    }
    if (last < text.length) out.add(TextSpan(text: text.substring(last)));
    return out;
  }

  Widget _rich(String text, TextStyle style) => Text.rich(TextSpan(style: style, children: _spans(text, style)));

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final jw = context.jw;
    final body = jw.text.body.copyWith(fontSize: 15.5, height: 1.45, color: jw.textPrimary);
    final children = <Widget>[];
    for (final (i, b) in _blocks.indexed) {
      final first = i == 0;
      switch (b) {
        case LegalHeading(level: 1):
          children.add(Padding(
            padding: EdgeInsets.only(top: first ? 0 : 18, bottom: 12),
            child: Semantics(header: true, child: _rich(b.text, jw.text.h2.copyWith(fontSize: 24, height: 1.2))),
          ));
        case LegalHeading(level: 2):
          children.add(Padding(
            padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 8),
            child: Semantics(header: true, child: _rich(b.text, jw.text.h3.copyWith(fontSize: 19, height: 1.25))),
          ));
        case LegalHeading():
          children.add(Padding(
            padding: EdgeInsets.only(top: first ? 0 : 12, bottom: 6),
            child: Semantics(
              header: true,
              child: _rich(b.text, jw.text.callout.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.3)),
            ),
          ));
        case LegalParagraph():
          children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: _rich(b.text, body)));
        case LegalBullet():
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Centre the dot on the first line at any text scale.
                  padding: EdgeInsets.only(top: MediaQuery.textScalerOf(context).scale(body.fontSize! * body.height!) / 2 - 3.5, right: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: jw.accent, shape: BoxShape.circle),
                    child: const SizedBox.square(dimension: 7),
                  ),
                ),
                Expanded(child: _rich(b.text, body)),
              ],
            ),
          ));
        case LegalTable():
          children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: _table(b, body)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  /// Each row as a sunken card: the first cell as its title, the others
  /// under their column's header (fits any width, no horizontal scroll).
  Widget _table(LegalTable t, TextStyle body) {
    final jw = context.jw;
    final label = jw.text.eyebrow.copyWith(fontSize: 11.5, color: jw.textMuted);
    final cellStyle = body.copyWith(fontSize: 14.5, height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in t.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: jw.clay(ClayLevel.sunken, radius: 16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (row.isNotEmpty) _rich(row.first, cellStyle.copyWith(fontWeight: FontWeight.w700)),
                    for (var c = 1; c < row.length; c++) ...[
                      const SizedBox(height: 8),
                      if (c < t.header.length) Text(t.header[c].toUpperCase(), style: label),
                      const SizedBox(height: 2),
                      _rich(row[c], cellStyle),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small centred "Terms of use · Refund policy" links that open the in-app
/// [LegalScreen]s (store fine print, account screen).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, required this.docs, this.onOpen, this.onHaptic, this.fontSize = 13.5});

  final List<LegalDoc> docs;

  /// Defaults to pushing `/legal/<doc>`.
  final void Function(LegalDoc doc)? onOpen;
  final VoidCallback? onHaptic;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final style = jw.text.caption.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: jw.purpleText,
      decoration: TextDecoration.underline,
      decorationColor: jw.purpleText,
    );
    final children = <Widget>[];
    for (final (i, doc) in docs.indexed) {
      if (i > 0) {
        children.add(ExcludeSemantics(
          child: Text(' · ', style: jw.text.caption.copyWith(fontSize: fontSize, color: jw.textMuted)),
        ));
      }
      children.add(Semantics(
        link: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            onHaptic?.call();
            onOpen != null ? onOpen!(doc) : context.push(AppRoutes.legal(doc));
          },
          child: Padding(
            // A comfortable tap target around small text.
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(doc.title(l), style: style),
          ),
        ),
      ));
    }
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

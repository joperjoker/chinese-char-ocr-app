// Bidirectional expansion table for Chinese radical component forms.
//
// Component forms are the shapes radicals take INSIDE a compound character.
// They often look quite different from the same radical written standalone:
//
//   氵 (three water drops, printed on a left-side card)  ≠  水 (water standalone)
//   亻 (leaning person stroke, left card)                ≠  人 (person standalone)
//   讠 (simplified speech hook, left card)               ≠  言 (speech standalone)
//   忄 (heart three strokes, left card)                  ≠  心 (heart standalone)
//   扌 (hand hook, left card)                            ≠  手 (hand standalone)
//
// ML Kit OCR is trained on full characters and may output the standalone form
// when the card actually shows the component form, or vice versa. This table
// lets the composition search cover both forms for every OCR candidate.

/// Maps a character that OCR might output → the alternative forms the card
/// might actually be showing. Both directions are listed so expansion works
/// regardless of whether OCR reads the component or the standalone form.
const Map<String, List<String>> kComponentVariants = {
  // ── Water / Ice ──────────────────────────────────────────────────────────
  '水': ['氵'],       // standalone → three-drop left component
  '氵': ['水', '冫'], // component may also be confused with two-drop ice
  '冰': ['冫'],
  '冫': ['冰', '水', '氵'],

  // ── Person ───────────────────────────────────────────────────────────────
  '人': ['亻'],       // standalone → leaning-stroke left component
  '亻': ['人'],

  // ── Speech / Words ───────────────────────────────────────────────────────
  '言': ['讠'],       // traditional/standalone → simplified left component
  '讠': ['言'],

  // ── Metal / Gold ─────────────────────────────────────────────────────────
  '金': ['钅'],       // standalone → simplified left component (钱铁铜...)
  '钅': ['金'],

  // ── Thread / Silk ────────────────────────────────────────────────────────
  '糸': ['纟'],       // traditional/standalone → simplified left component
  '纟': ['糸', '丝'],
  '丝': ['纟'],

  // ── Heart / Mind ─────────────────────────────────────────────────────────
  '心': ['忄'],       // standalone → three-stroke left component (快情怕...)
  '忄': ['心'],

  // ── Hand ─────────────────────────────────────────────────────────────────
  '手': ['扌'],       // standalone → hook left component (打找拿...)
  '扌': ['手'],

  // ── Dog ──────────────────────────────────────────────────────────────────
  '犬': ['犭'],       // standalone → three-stroke left component (猫狗狐...)
  '犭': ['犬'],

  // ── Spirit / Deity ───────────────────────────────────────────────────────
  '示': ['礻'],       // standalone → two-dot left component (神礼福...)
  '礻': ['示'],

  // ── Clothing ─────────────────────────────────────────────────────────────
  '衣': ['衤'],       // standalone → split left component (裙裤被...)
  '衤': ['衣'],

  // ── Food (simplified) ────────────────────────────────────────────────────
  '食': ['饣'],       // standalone → simplified left component (饭饿馆...)
  '饣': ['食'],

  // ── Knife ────────────────────────────────────────────────────────────────
  '刀': ['刂'],       // standalone → upright right component (到利别...)
  '刂': ['刀'],

  // ── Fire ─────────────────────────────────────────────────────────────────
  '火': ['灬'],       // standalone → four-dot bottom component (热点煮...)
  '灬': ['火'],

  // ── Flesh (looks like moon when used as component) ───────────────────────
  '肉': ['月'],       // flesh radical is visually identical to 月 as a component
  '月': ['肉'],       // 月 may mean "moon" or be the flesh component (脸胖脑...)

  // ── Walk / Step ──────────────────────────────────────────────────────────
  '行': ['彳'],       // full "walk" → left half component
  '彳': ['行'],

  // ── Grass (top component) ────────────────────────────────────────────────
  '草': ['艹'],
  '艹': ['草'],

  // ── Cow / Ox ─────────────────────────────────────────────────────────────
  '牛': ['牜'],
  '牜': ['牛'],

  // ── Eye ──────────────────────────────────────────────────────────────────
  // 目 stays the same as component; no expansion

  // ── Foot / Walk (bottom) ─────────────────────────────────────────────────
  '走': ['辶'],
  '辶': ['走', '之'],
  '之': ['辶'],
};

/// Maps a left/right radical *component form* → the full standalone character
/// it is the reduced form of. Used to enrich a recognised side with its "full
/// character version": a card showing 氵 (which has no reading or meaning on its
/// own) is the reduced form of 水 (shuǐ, water), so the result can show both.
///
/// Only forms that genuinely differ from a standalone character are listed; a
/// side that already is a full character (女, 子, 工, 口 …) is absent and needs
/// no enrichment.
const Map<String, String> kComponentToStandalone = {
  '氵': '水', // water
  '冫': '冰', // ice
  '亻': '人', // person
  '讠': '言', // speech
  '钅': '金', // metal / gold
  '纟': '糸', // silk
  '忄': '心', // heart
  '扌': '手', // hand
  '犭': '犬', // dog / beast
  '礻': '示', // spirit / altar
  '衤': '衣', // clothing
  '饣': '食', // food / eat
  '刂': '刀', // knife (right-side form)
};

/// The full standalone character a side [component] is the reduced form of, or
/// null when the side is already a full character (or unknown).
String? fullCharacterOf(String component) => kComponentToStandalone[component];

/// Returns [candidates] expanded to include known component/standalone variants
/// of each character, preserving original rank order (each original precedes
/// its variants so the best OCR guess still has priority).
List<String> expandWithComponentVariants(List<String> candidates) {
  final seen = <String>{};
  final expanded = <String>[];
  for (final c in candidates) {
    if (seen.add(c)) expanded.add(c);
    final variants = kComponentVariants[c];
    if (variants != null) {
      for (final v in variants) {
        if (seen.add(v)) expanded.add(v);
      }
    }
  }
  return expanded;
}

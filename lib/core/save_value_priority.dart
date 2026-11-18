/// Conservative, name-based hints for save values. These are labels, not
/// assertions that a value is a real game statistic or safe to edit.
enum SaveValueCategory {
  currency('Валюта', 0),
  health('HP / здоровье', 1),
  mana('Мана / MP', 2),
  attributes('Характеристики', 3),
  level('Уровень', 4),
  experience('Опыт', 5),
  resources('Ресурсы', 6),
  other('', 99);

  const SaveValueCategory(this.label, this.priority);
  final String label;
  final int priority;

  bool get important => this != other;
}

class SaveValuePriority {
  const SaveValuePriority._();

  static const _currency = <String>{
    'gold', 'coin', 'coins', 'money', 'currency', 'wallet', 'cash',
    'credit', 'credits', 'gems', 'gem', 'crystal', 'crystals',
    'diamond', 'diamonds', 'silver', 'gil', 'mora', 'primogems',
    'монеты', 'монета', 'деньги', 'валюта', 'золото', 'кристаллы',
  };
  static const _health = <String>{
    'hp', 'health', 'hitpoints', 'life', 'lives',
    'здоровье', 'жизни', 'жизнь', 'хп',
  };
  static const _mana = <String>{
    'mp', 'mana', 'magicka', 'magicpoints', 'мана', 'магия',
  };
  static const _attributes = <String>{
    'stat', 'stats', 'attribute', 'attributes', 'strength', 'str',
    'dexterity', 'dex', 'agility', 'agi', 'intelligence', 'int',
    'vitality', 'vit', 'wisdom', 'wis', 'luck', 'charisma', 'defense',
    'defence', 'attack', 'atk', 'armor', 'armour', 'crit',
    'criticals', 'damage', 'dmg', 'resistance',
    'сила', 'ловкость', 'интеллект', 'удача', 'атака', 'защита',
    'броня', 'статы', 'характеристики',
  };
  static const _level = <String>{
    'level', 'lvl', 'rank', 'уровень', 'ранг',
  };
  static const _experience = <String>{
    'xp', 'exp', 'experience', 'опыт',
  };
  static const _resources = <String>{
    'stamina', 'energy', 'endurance', 'hunger', 'thirst',
    'stamina', 'силавыносливость', 'выносливость', 'энергия',
    'голод', 'жажда',
  };

  /// Splits camelCase, PascalCase, underscores and JSON Pointer segments;
  /// matching whole tokens prevents false positives such as "shop" => HP
  /// or "goldenRatio" => gold.
  static List<String> _tokens(String path) {
    final decoded = path.replaceAll('~1', '/').replaceAll('~0', '~');
    final separated = decoded
        .replaceAllMapped(RegExp(r'([A-Z])([A-Z][a-z])'),
            (match) => '${match[1]} ${match[2]}')
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'),
            (match) => '${match[1]} ${match[2]}')
        .toLowerCase();
    return separated.split(RegExp(r'[^a-z0-9а-яё]+'))
        .where((s) => s.isNotEmpty && int.tryParse(s) == null)
        .toList(growable: false);
  }

  static SaveValueCategory fromPath(String pointer, Object? value) {
    // Game stats are numeric in the generic editor. Titles, translations and
    // boolean flags must never be presented as editable HP or money.
    if (value is! num || !value.isFinite) return SaveValueCategory.other;
    return fromName(pointer);
  }

  static SaveValueCategory fromName(String path) {
    final tokens = _tokens(path);
    bool any(Set<String> keys) => tokens.any(keys.contains);
    if (any(_currency)) return SaveValueCategory.currency;
    if (any(_health)) return SaveValueCategory.health;
    if (any(_mana)) return SaveValueCategory.mana;
    if (any(_attributes)) return SaveValueCategory.attributes;
    if (any(_level)) return SaveValueCategory.level;
    if (any(_experience)) return SaveValueCategory.experience;
    if (any(_resources)) return SaveValueCategory.resources;
    return SaveValueCategory.other;
  }
}

import 'package:kazumi/modules/media/media_rule.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/legacy_rule_adapter.dart';

/// Extension on [Plugin] providing conversion to the universal [MediaRule].
///
/// Defined as an extension (in a separate file from [Plugin]) to avoid
/// circular imports between [plugins.dart] and [legacy_rule_adapter.dart].
extension PluginMediaRuleConversion on Plugin {
  /// Converts this legacy [Plugin] rule to a universal [MediaRule] (v9 schema)
  /// via [LegacyRuleAdapter].
  ///
  /// The new [MediaRuleEngine] can accept the returned [MediaRule] directly,
  /// enabling the universal media layer to work with existing rules without
  /// modifying their storage format.
  MediaRule toMediaRule() {
    return LegacyRuleAdapter.fromPlugin(this);
  }
}

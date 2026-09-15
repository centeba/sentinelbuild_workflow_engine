// Schema-export tool — generates two JSON files that pages-api's AI
// generator includes verbatim in its system prompts:
//
//   - `schema/page_definition.schema.json` — JSON Schema describing the
//     PageDefinition / PageElement / supporting model shape so Claude
//     emits well-formed JSON.
//   - `schema/element_types.json` — for every PageElementType, its label,
//     description, category, and the default config keys + types.
//     Lets Claude pick a sensible config for each element.
//
// Run from the repo root:
//   dart run packages/web_builder_renderer/tools/export_schema.dart
//
// The output files are committed so pages-api ships with them. Re-run
// whenever models or kElementRegistry change.

import 'dart:convert';
import 'dart:io';

import 'package:web_builder_renderer/web_builder_renderer.dart';

void main() {
  final outDir = Directory('packages/web_builder_renderer/schema');
  outDir.createSync(recursive: true);

  final schema = _buildPageSchema();
  File('${outDir.path}/page_definition.schema.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(schema),
  );

  final types = _buildElementTypeCatalog();
  File('${outDir.path}/element_types.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(types),
  );

  // Sanity: confirm enums + registry are in sync.
  final missing = <String>[];
  for (final t in PageElementType.values) {
    if (!types.containsKey(t.name)) missing.add(t.name);
  }
  if (missing.isNotEmpty) {
    stderr.writeln(
      'WARNING — these PageElementType values have no entry in '
      'kElementRegistry: ${missing.join(', ')}. They will be invisible '
      "to Claude's prompt and untouchable by AI generation.",
    );
  }

  stdout.writeln('Wrote ${outDir.path}/page_definition.schema.json');
  stdout.writeln('Wrote ${outDir.path}/element_types.json');
  stdout.writeln('Element types catalogued: ${types.length}');
}

// ──────────────────────────────────────────────────────────────────────────────
// JSON Schema generator
//
// Hand-written rather than reflective — the Dart models don't carry
// JSON-Schema annotations and `dart:mirrors` is unavailable on web. The
// shape mirrors PageDefinition.toJson + PageElement.toJson + supporting
// classes. When a new field lands on those models, update this function.
// ──────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _buildPageSchema() {
  return {
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'title': 'PageDefinition',
    'description':
        'Top-level page authored in the SentinelBuild web-builder. The '
        'renderer takes this verbatim and produces a Flutter widget '
        'tree.',
    'type': 'object',
    'required': ['id', 'title'],
    'properties': {
      'id': {'type': 'string', 'description': 'UUID. Generate fresh.'},
      'title': {'type': 'string'},
      'slug': {
        'type': 'string',
        'description':
            'URL slug for the page within its site. Lowercase, '
            'hyphen-separated.',
      },
      'order': {'type': 'integer', 'default': 0},
      'sections': {
        'type': 'array',
        'items': _sectionSchema(),
      },
      'elements': {
        'type': 'array',
        'items': _elementSchema(),
      },
      'inputParams': {
        'type': 'array',
        'items': _paramSchema(),
        'description': 'Page-level input parameters, e.g. route params.',
      },
      'parentPageId': {'type': ['string', 'null']},
      'publicAccess': {
        'type': 'boolean',
        'default': false,
        'description':
            'Anonymous access flag. Only platform/system admins can '
            'flip this to true via the server.',
      },
      'rateLimits': {
        'type': ['object', 'null'],
        'properties': {
          'per_min': {'type': 'integer'},
          'per_day': {'type': 'integer'},
        },
      },
      'captchaConfig': {
        'type': ['object', 'null'],
        'properties': {
          'provider': {'type': 'string', 'enum': ['recaptcha_v3']},
          'site_key': {'type': 'string'},
          'min_score': {'type': 'number'},
        },
      },
      'submissionConfig': {
        'type': ['object', 'null'],
        'properties': {
          'max_size_kb': {'type': 'integer'},
          'max_fields': {'type': 'integer'},
        },
      },
      'roleVisibility': {
        'type': ['array', 'null'],
        'items': {'type': 'string'},
        'description':
            'Restrict the whole page to viewers carrying at least one '
            'of these roles. Empty/null = visible to all auth users.',
      },
      'onSubmit': {
        'type': ['object', 'null'],
        'description':
            'Optional server-side action fired when a public form on '
            'this page is submitted. Pages-api dispatches this; the '
            'client never gets to call workflow triggers directly.',
        'properties': {
          'type': {
            'type': 'string',
            'enum': ['trigger_workflow', 'http_post'],
          },
          'workflow_id': {'type': 'string'},
          'url': {'type': 'string'},
          'headers': {'type': 'object'},
        },
      },
    },
  };
}

Map<String, dynamic> _sectionSchema() => {
      'type': 'object',
      'required': ['id', 'pageId'],
      'properties': {
        'id': {'type': 'string'},
        'pageId': {'type': 'string'},
        'title': {'type': 'string'},
        'description': {'type': 'string'},
        'order': {'type': 'integer'},
        'collapsible': {'type': 'boolean'},
        'collapsed': {'type': 'boolean'},
        'style': _styleSchema(),
      },
    };

Map<String, dynamic> _elementSchema() => {
      'type': 'object',
      'required': ['id', 'type'],
      'properties': {
        'id': {'type': 'string'},
        'type': {
          'type': 'string',
          'enum': PageElementType.values.map((t) => t.name).toList(),
          'description':
              'See element_types.json for the per-type config keys and '
              'default values. Use only types listed there.',
        },
        'sectionId': {'type': ['string', 'null']},
        'rowIndex': {'type': 'integer', 'default': 0},
        'colWidth': {
          'type': 'integer',
          'default': 12,
          'description': 'Width in a 12-column grid (1-12).',
        },
        'config': {
          'type': 'object',
          'description':
              'Per-type configuration. See element_types.json.',
        },
        'style': _styleSchema(),
        'dataBinding': _dataBindingSchema(),
        'conditional': {
          'type': ['object', 'null'],
          'description':
              'Show/hide rules. Shape: {action: show|hide, combinator: '
              'and|or, conditions: [{field, operator, value}, ...]}.',
        },
        'responsive': {
          'type': 'object',
          'description':
              'Per-breakpoint overrides keyed by breakpoint name '
              "('mobile', 'tablet', 'desktop').",
        },
        'children': {
          'type': ['array', 'null'],
          r'items': {r'$ref': '#/definitions/element'},
        },
        'action': _navigationActionSchema(),
        'roleVisibility': {
          'type': ['array', 'null'],
          'items': {'type': 'string'},
          'description':
              'Element-level role gate. Renderer hides the element when '
              "the active session's roles don't intersect this list.",
        },
      },
    };

Map<String, dynamic> _paramSchema() => {
      'type': 'object',
      'required': ['key', 'type'],
      'properties': {
        'key': {'type': 'string'},
        'type': {
          'type': 'string',
          'enum': ['string', 'number', 'boolean', 'object'],
        },
        'defaultValue': {},
        'required': {'type': 'boolean'},
      },
    };

Map<String, dynamic> _styleSchema() => {
      'type': ['object', 'null'],
      'description':
          'Visual styling. Common keys: paddingTop/paddingBottom/'
          'paddingLeft/paddingRight, marginTop/marginBottom/marginLeft/'
          'marginRight, fontSize, fontWeight, color, backgroundColor, '
          'borderColor, borderWidth, borderRadius, opacity, '
          'textAlign, width, height, minHeight.',
    };

Map<String, dynamic> _dataBindingSchema() => {
      'type': ['object', 'null'],
      'description':
          'HTTP data binding. The renderer fetches `url` and substitutes '
          'the response into any `{{...}}` token in the element config. '
          'URLs and headers support tokens like `{{route.x}}`, '
          '`{{session.token}}`, `{{form.x}}`, `{{api.<source>.<path>}}`.',
      'properties': {
        'url': {'type': 'string'},
        'method': {
          'type': 'string',
          'enum': ['get', 'post', 'put', 'delete', 'patch'],
          'default': 'get',
        },
        'headers': {'type': 'object'},
        'body': {'type': ['string', 'null']},
        'responsePath': {
          'type': 'string',
          'default': r'$',
          'description': 'JSONPath into the response body.',
        },
        'pollingIntervalSeconds': {'type': ['integer', 'null']},
        'fetchOnLoad': {'type': 'boolean', 'default': true},
        'triggerElementId': {'type': ['string', 'null']},
        'refreshOn': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'EventBus event names that trigger a re-fetch (e.g. '
              "'form.submitted').",
        },
        'subscribe': {
          'type': ['string', 'null'],
          'description':
              'WebSocket channel template for real-time updates.',
        },
      },
    };

Map<String, dynamic> _navigationActionSchema() => {
      'type': ['object', 'null'],
      'description':
          'Action fired when this element is interacted with. Common '
          'shapes: {type: navigate, to: <pageId or url>}, '
          '{type: form_submit, method, url, body, onSuccess, onError}, '
          '{type: open_modal, modalId}.',
    };

// ──────────────────────────────────────────────────────────────────────────────
// Element-type catalog — derived from kElementRegistry so it stays in sync
// with whatever the designer can drag onto a canvas.
// ──────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _buildElementTypeCatalog() {
  final out = <String, dynamic>{};
  for (final meta in kElementRegistry) {
    out[meta.type.name] = {
      'label': meta.label,
      'description': meta.description,
      'category': meta.category.name,
      'defaultConfig': meta.defaultConfig,
    };
  }
  return out;
}

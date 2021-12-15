import 'package:collection/collection.dart' show IterableExtension;

import 'group.dart';
import 'mirror_argument_pair.dart';
import 'parser.dart';
import 'predicates.dart';
import 'string_utils.dart';

/// Removes consecutive lines from the provided [list] where the value is ''
List<String?> removeConsecutiveBlanks(final List<String?> list) {
  if (list.isEmpty) {
    return list;
  }
  List<String?> newList = [list[0]];
  var index = 1;
  while (index < list.length) {
    var prev = list[index - 1];
    var item = list[index];
    if (isFalse((prev == '') && (prev == item))) {
      newList.add(item);
    }
    index++;
  }
  return newList;
}

List<String?> _keys(final Parser? _app, final MirrorParameterPair mpp) {
  return mpp.keys(_app).map((v) => v!.startsWith('-') ? v : '--$v').toList();
}

String? argumentHelp(final MirrorParameterPair mpp) {
  return mpp.argument.help ??
      (mpp.mirror.type.metadata
                  .firstWhereOrNull((element) => element.runtimeType == Parser)
              as Parser?)
          ?.description;
}

List<String?> commands(
  Iterable<MirrorParameterPair> commands, {
  required final int helpLineWidth,
  required final int optionColumnWidth,
  required final String linePrefix,
}) {
  if (commands.isEmpty) {
    return [];
  }
  List<String?> lines = ['', 'COMMANDS'];
  List<MirrorParameterPair>.from(commands)
      .sortedBy((mpp) => mpp.displayKey!)
      .forEach((mpp) {
    final String? help = argumentHelp(mpp);
    final commandDisplay = '$linePrefix${mpp.displayKey!}';
    var commandHelp = hardWrap(
      help ?? '',
      helpLineWidth,
    );
    commandHelp = indent(commandHelp, optionColumnWidth);
    if (commandDisplay.length <= optionColumnWidth - 1) {
      commandHelp = commandHelp.replaceRange(
        0,
        commandDisplay.length,
        commandDisplay,
      );
    } else {
      lines.add(commandDisplay);
    }
    lines.add(commandHelp);
  });
  return lines;
}

List<String?> arguments(
  final Parser? app,
  final Iterable<MirrorParameterPair> arguments, {
  required final int helpLineWidth,
  required final int optionColumnWidth,
  required final String linePrefix,
  required final int lineIndent,
  required final int lineWidth,
}) {
  if (arguments.isEmpty) {
    return [];
  }
  List<String?> lines = [];

  List<String> helpKeys = [];
  List<Group?> helpGroups = [];
  List<List<String>> helpDescriptions = [];

  for (var mpp in arguments) {
    List<String?> keys = [];
    keys.addAll(_keys(app, mpp));

    List<String> helpLines = [mpp.argument.help ?? 'no help available'];
    if (mpp.argument.isRequired ?? false) {
      helpLines.add('[REQUIRED]');
    }
    String? envVar = mpp.argument.environmentVariable;
    if (isNotBlank(envVar)) {
      helpLines.add('[Environment Variable: \$$envVar]');
    }
    helpLines.addAll(mpp.argument.additionalHelpLines);

    helpKeys.add(keys.join(', '));
    helpGroups.add(mpp.group);
    helpDescriptions.add(helpLines);
  }

  void trailingHelp(Group? group) {
    if (isNotNull(group?.afterHelp)) {
      lines.add('');
      lines.add(
        indent(
          hardWrap(group!.afterHelp!, lineWidth - lineIndent),
          lineIndent,
        ),
      );
    }
  }

  Group? currentGroup;

  for (var i = 0; i < helpKeys.length; i++) {
    final thisGroup = helpGroups[i];

    if (thisGroup != currentGroup) {
      trailingHelp(currentGroup);

      if (isNotNull(currentGroup)) {
        lines.add('');
      }

      lines.add(thisGroup!.name);

      if (isNotNull(thisGroup.beforeHelp)) {
        lines.add(
          indent(
            hardWrap(thisGroup.beforeHelp!, lineWidth - lineIndent),
            lineIndent,
          ),
        );
        lines.add('');
      }
    }

    var keyDisplay = linePrefix + helpKeys[i];

    var thisHelpDescriptions = helpDescriptions[i].join('\n');
    thisHelpDescriptions = hardWrap(thisHelpDescriptions, helpLineWidth);
    thisHelpDescriptions = indent(thisHelpDescriptions, optionColumnWidth);
    if (keyDisplay.length <= optionColumnWidth - 1) {
      thisHelpDescriptions = thisHelpDescriptions.replaceRange(
        0,
        keyDisplay.length,
        keyDisplay,
      );
    } else {
      lines.add(keyDisplay);
    }
    lines.add(thisHelpDescriptions);
    currentGroup = helpGroups[i] ?? currentGroup;
  }

  trailingHelp(currentGroup);
  return lines;
}

List<String?> argument(
  final Parser? app,
  final MirrorParameterPair mpp, {
  required final int helpLineWidth,
  required final int optionColumnWidth,
  required final String linePrefix,
}) {
  List<String?> lines = [];
  String keys = _keys(app, mpp).join(', ');
  List<String> helpLines = [mpp.argument.help ?? 'no help available'];
  if (mpp.argument.isRequired ?? false) {
    helpLines.add('[REQUIRED]');
  }
  String? envVar = mpp.argument.environmentVariable;
  if (isNotBlank(envVar)) {
    helpLines.add('[Environment Variable: \$$envVar]');
  }
  helpLines.addAll(mpp.argument.additionalHelpLines);
  var keyDisplay = linePrefix + keys;
  var thisHelpDescriptions = helpLines.join('\n');
  thisHelpDescriptions = hardWrap(thisHelpDescriptions, helpLineWidth);
  thisHelpDescriptions = indent(thisHelpDescriptions, optionColumnWidth);
  if (keyDisplay.length <= optionColumnWidth - 1) {
    thisHelpDescriptions = thisHelpDescriptions.replaceRange(
      0,
      keyDisplay.length,
      keyDisplay,
    );
  } else {
    lines.add(keyDisplay);
  }
  lines.add(thisHelpDescriptions);
  return lines;
}

List<String?> options(
  final Parser? app,
  final Iterable<MirrorParameterPair> options, {
  required final int helpLineWidth,
  required final int optionColumnWidth,
  required final String linePrefix,
}) {
  if (options.isEmpty) {
    return [];
  }
  List<String?> lines = ['', 'OPTIONS'];
  for (MirrorParameterPair mpp in options) {
    lines.addAll(
      argument(
        app,
        mpp,
        optionColumnWidth: optionColumnWidth,
        linePrefix: linePrefix,
        helpLineWidth: helpLineWidth,
      ),
    );
  }
  return lines;
}

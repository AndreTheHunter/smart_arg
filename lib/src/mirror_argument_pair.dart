import 'package:reflectable/mirrors.dart';

import 'argument.dart';
import 'command.dart';
import 'group.dart';
import 'parser.dart';
import 'predicates.dart';

// Convert `areYouAlive` to `are-you-alive`
String camelToDash(String value) {
  var r = RegExp(r'(^.|[A-Z])[^A-Z]*');
  var indexes = r.allMatches(value);
  var result = [];

  for (var index in indexes) {
    result.add(value.substring(index.start, index.end));
  }

  return result.join('-').toLowerCase();
}

class MirrorParameterPair {
  final VariableMirror mirror;
  final Argument argument;
  final Group? group;

  String? displayKey;

  MirrorParameterPair(this.mirror, this.argument, [this.group]);

  List<String?> keys(Parser? parser) {
    // Local type is needed, otherwise result winds up being a
    // List<dynamic> which is incompatible with the return type.
    // Therefore, ignore the suggestion from dartanalyzer
    //
    // ignore: omit_local_variable_types
    List<String?> result = [];

    String? long;
    String? short;

    if (argument.short != null) {
      short = argument.short;

      result.add('-$short');
    }

    if (argument.long == null && parser!.strict != true) {
      long = camelToDash(mirror.simpleName);

      result.add(long);
    } else if (argument.long is String) {
      long = argument.long;

      result.add(long);
    }

    result.addAll(argument.specialKeys(short, long));

    displayKey = long is String ? long : short;

    if (displayKey == null) {
      throw StateError('No key could be found for ${mirror.simpleName})');
    } else if (short?.startsWith('-') ?? false) {
      throw StateError(
        'Short key ($short) defined by short: should not include a leading -',
      );
    } else if (long?.startsWith('-') ?? false) {
      throw StateError(
        'Long key ($short) defined by long: should not include a leading -',
      );
    }

    return result;
  }
}

/// True if the provided [Object] is a [Group]
bool isGroup(final Object object) {
  return object is Group;
}

/// True if the provided [Object] is an [Argument]
bool isArgument(final Object object) {
  return object is Argument;
}

/// True if the provided [MirrorParameterPair] is an option type [Argument]
bool isOption(final MirrorParameterPair mpp) {
  return isTrue(mpp.argument.isOption);
}

/// True if the provided [MirrorParameterPair] is NOT an option type [Argument]
bool isNotOption(final MirrorParameterPair mpp) {
  return isFalse(isOption(mpp));
}

/// True if the provided [MirrorParameterPair] or [Argument] is of type [Command]
bool isCommand(final dynamic mpp) {
  if (mpp is MirrorParameterPair) {
    return mpp.argument is Command;
  } else if (mpp is Argument) {
    return mpp is Command;
  } else {
    return false;
  }
}

/// True if the provided [MirrorParameterPair] is NOT of type [Command]
bool isNotCommand(final MirrorParameterPair mpp) {
  return isFalse(isCommand(mpp));
}

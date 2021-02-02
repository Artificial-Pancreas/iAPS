#! /bin/sh

function assertEnvironment {
	if [ -z $1 ]; then 
		echo $2
		exit 127
	fi
}

assertEnvironment "${SRCROOT}" "Please set SRCROOT to project root folder"

SDKROOT=macosx

swift run -c release --package-path BuildTools swiftformat "${SRCROOT}" \
--enable andOperator,\
anyObjectProtocol,\
blankLinesAroundMark,\
blankLinesAtEndOfScope,\
blankLinesAtStartOfScope,\
blankLinesBetweenScopes,\
consecutiveBlankLines,\
consecutiveSpaces,\
duplicateImports,\
elseOnSameLine,\
emptyBraces,\
fileHeader,\
hoistPatternLet,\
indent,\
isEmpty,\
leadingDelimiters,\
linebreakAtEndOfFile,\
linebreaks,\
numberFormatting,\
redundantBackticks,\
redundantBreak,\
redundantExtensionACL,\
redundantFileprivate,\
redundantGet,\
redundantInit,\
redundantLet,\
redundantLetError,\
redundantNilInit,\
redundantObjc,\
redundantParens,\
redundantPattern,\
redundantRawValues,\
redundantReturn,\
redundantSelf,\
redundantVoidReturnType,\
semicolons,\
sortedImports,\
spaceAroundBraces,\
spaceAroundBrackets,\
spaceAroundComments,\
spaceAroundGenerics,\
spaceAroundOperators,\
spaceAroundParens,\
spaceInsideBraces,\
spaceInsideBrackets,\
spaceInsideComments,\
spaceInsideGenerics,\
spaceInsideParens,\
specifiers,\
strongifiedSelf,\
strongOutlets,\
todos,\
trailingCommas,\
trailingSpace,\
typeSugar,\
unusedArguments,\
void,\
wrap,\
wrapArguments \
--disable braces,\
trailingClosures \
--commas inline \
--empty void \
--exponentcase uppercase \
--header strip \
--hexliteralcase uppercase \
--ifdef indent \
--indent 4 \
--self remove \
--semicolons never \
--swiftversion 5.2 \
--trimwhitespace always \
--maxwidth 130 \
--wraparguments before-first \
--wrapcollections before-first \
--exclude Pods,Generated,R.generated.swift,fastlane/swift

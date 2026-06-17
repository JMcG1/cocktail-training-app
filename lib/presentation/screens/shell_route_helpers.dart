import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/firestore/firestore_serializers.dart';
import '../../domain/models/models.dart';

String? sessionIdFromUri(Uri uri) {
  final pathSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  return uri.queryParameters['session'] ??
      (pathSegments.length >= 2 && pathSegments.first == 'quiz'
          ? pathSegments[1]
          : null);
}

class InviteRouteData {
  const InviteRouteData({required this.venueId, required this.inviteId});

  final String venueId;
  final String inviteId;
}

InviteRouteData? inviteRouteFromUri(Uri uri) {
  final pathSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (pathSegments.length >= 3 && pathSegments.first == 'join') {
    return InviteRouteData(venueId: pathSegments[1], inviteId: pathSegments[2]);
  }
  final venueId = uri.queryParameters['venue'];
  final inviteId = uri.queryParameters['invite'];
  if ((venueId ?? '').isNotEmpty && (inviteId ?? '').isNotEmpty) {
    return InviteRouteData(venueId: venueId!, inviteId: inviteId!);
  }
  return null;
}

Uri inviteLinkUriFromBase(Uri baseUri, VenueInvite invite) {
  return baseUri.replace(
    queryParameters: {'venue': invite.venueId, 'invite': invite.id},
    fragment: null,
  );
}

Uri quizLinkUriFromBase(Uri baseUri, QuizSession session) {
  final preservedSegments = baseUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  return baseUri.replace(
    pathSegments: [...preservedSegments, 'quiz', session.id],
    queryParameters: null,
    fragment: null,
  );
}

String approvedRecipesExportJson(List<CocktailRecipe> recipes) {
  return const JsonEncoder.withIndent('  ').convert(
    recipes
        .map(
          (recipe) => {
            'id': recipe.id,
            ...FirestoreSerializers.recipeToMap(recipe),
          },
        )
        .toList(),
  );
}

String weeklyResultsExportJson(List<QuizAttempt> attempts) {
  return const JsonEncoder.withIndent('  ').convert(
    attempts
        .map(
          (attempt) => {
            'id': attempt.id,
            ...FirestoreSerializers.quizAttemptToMap(attempt),
          },
        )
        .toList(),
  );
}

Future<void> showShareLinkDialog({
  required BuildContext context,
  required String title,
  required String url,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(url, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: url,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Link copied.')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy link'),
        ),
      ],
    ),
  );
}

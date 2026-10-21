import 'package:flutter/material.dart';

import '../../models/influencer_campaign_model.dart';
import '../../services/influencer_campaign_service.dart';

class InfluencerRecentCampaignsWidget extends StatelessWidget {
  final String userId;

  const InfluencerRecentCampaignsWidget({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InfluencerCampaignModel>>(
      future: InfluencerCampaignService().getVideos(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Text("Failed to load videos");
        }

        final videos = snapshot.data ?? [];

        if (videos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text("No videos uploaded yet")),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...videos.map(
              (video) => Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded),
                  title: Text(video.title),
                  subtitle: Text(video.description),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility, size: 18),
                      Text(video.views.toString()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

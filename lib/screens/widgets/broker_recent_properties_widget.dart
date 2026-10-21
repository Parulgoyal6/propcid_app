import 'package:flutter/material.dart';

import '../../models/broker_property_model.dart';
import '../../services/broker_property_service.dart';

class BrokerRecentPropertiesWidget extends StatelessWidget {
  final String brokerId;

  const BrokerRecentPropertiesWidget({super.key, required this.brokerId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BrokerPropertyModel>>(
      future: BrokerPropertyService().getProperties(brokerId),

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
          return const Text("Failed to load properties");
        }

        final properties = snapshot.data ?? [];

        if (properties.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(25),
              child: Text(
                "No Properties Found",
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...properties.map(
              (property) => Card(
                margin: const EdgeInsets.only(bottom: 16),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    if (property.image.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),

                        child: Image.network(
                          property.image,
                          width: double.infinity,
                          height: 190,
                          fit: BoxFit.cover,
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(16),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            property.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(property.location),

                          const SizedBox(height: 14),

                          Row(
                            children: [
                              Chip(label: Text(property.status)),

                              const Spacer(),

                              const Icon(Icons.visibility),

                              const SizedBox(width: 4),

                              Text(property.views.toString()),

                              const SizedBox(width: 16),

                              const Icon(Icons.favorite, color: Colors.red),

                              const SizedBox(width: 4),

                              Text(property.likes.toString()),
                            ],
                          ),

                          const Divider(),

                          Text(
                            "₹${property.price.toStringAsFixed(0)}",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

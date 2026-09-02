import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';

class NotificationCenterPanel extends StatefulWidget {
  final List<ServiceNotificationEvent> notifications;
  final VoidCallback onClearAll;

  const NotificationCenterPanel({
    Key? key,
    required this.notifications,
    required this.onClearAll,
  }) : super(key: key);

  @override
  State<NotificationCenterPanel> createState() => _NotificationCenterPanelState();
}

class _NotificationCenterPanelState extends State<NotificationCenterPanel> {
  bool _isCalendarExpanded = false;

  Widget _buildNotificationCard({required IconData icon, required Color iconColor, required String title, required String body, required String time}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), // Slimmer padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    Text(time, style: const TextStyle(color: Colors.black45, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Colors.black54, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Notifications', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: widget.onClearAll,
                child: Text('Clear all', style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontWeight: FontWeight.w500)),
              )
            ],
          ),
          const SizedBox(height: 8),
          
          Flexible(
            child: widget.notifications.isEmpty 
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(child: Text("No new notifications", style: TextStyle(color: Colors.black54, fontSize: 12))),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.notifications.length,
                  itemBuilder: (context, index) {
                    final notification = widget.notifications[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: _buildNotificationCard(
                        icon: Icons.notifications, 
                        iconColor: Colors.blueAccent,
                        title: notification.title ?? 'System',
                        body: notification.content ?? 'New message received.',
                        time: 'Just now',
                      ),
                    );
                  },
                ),
          ),
          
          const Divider(color: Colors.black12, height: 16),
          
          InkWell(
            onTap: () => setState(() => _isCalendarExpanded = !_isCalendarExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${weekdays[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}', style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
                      const Text('No upcoming events today', style: TextStyle(color: Colors.black54, fontSize: 10)),
                    ],
                  ),
                  Icon(_isCalendarExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.black87, size: 18),
                ],
              ),
            ),
          ),
          
          AnimatedCrossFade(
            crossFadeState: _isCalendarExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.85, 
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 300, 
                    height: 320, 
                    child: Theme(
                      data: ThemeData.light().copyWith(
                        colorScheme: const ColorScheme.light(primary: Color(0xFF1871D9), onSurface: Colors.black87),
                      ),
                      child: CalendarDatePicker(
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        onDateChanged: (date) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
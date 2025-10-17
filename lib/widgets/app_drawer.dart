import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../screens/profile_page.dart';
import '../screens/attendance_list_page.dart';
import '../screens/add_student_page.dart';
import '../screens/instructor_attendance_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryColor,
              AppTheme.primaryDark,
            ],
          ),
        ),
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Logo
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/nutclogo.jpg',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to icon if image fails to load
                          return const Icon(
                            Icons.school,
                            size: 30,
                            color: Colors.white,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // App Name
                  const Text(
                    'Student Attendance',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  
                  // App Subtitle
                  Text(
                    'Manage student records',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),

            // Drawer Items
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  children: [
                    _buildDrawerItem(
                      context,
                      icon: Icons.dashboard_outlined,
                      title: 'Dashboard',
                      subtitle: 'Overview and statistics',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const AttendanceListPage()),
                        );
                      },
                    ),
                    
                    _buildDrawerItem(
                      context,
                      icon: Icons.people_outline,
                      title: 'Students',
                      subtitle: 'Manage student records',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AddStudentPage()),
                        );
                      },
                    ),
                    
                    _buildDrawerItem(
                      context,
                      icon: Icons.check_circle_outline,
                      title: 'Mark Attendance',
                      subtitle: 'Start attendance session',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const InstructorAttendancePage()),
                        );
                      },
                    ),
                    
                    _buildDrawerItem(
                      context,
                      icon: Icons.calendar_today_outlined,
                      title: 'Attendance',
                      subtitle: 'View attendance records',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const AttendanceListPage()),
                        );
                      },
                    ),
                    
                    _buildDrawerItem(
                      context,
                      icon: Icons.analytics_outlined,
                      title: 'Reports',
                      subtitle: 'Generate attendance reports',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reports coming soon!')),
                        );
                      },
                    ),
                    
                    const Divider(height: 32),
                    
                    _buildDrawerItem(
                      context,
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      subtitle: 'App preferences',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Settings coming soon!')),
                        );
                      },
                    ),
                    
                    _buildDrawerItem(
                      context,
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      subtitle: 'Get help and support',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Help & support coming soon!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Profile Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Admin User',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Administrator',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfilePage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: AppTheme.primaryColor,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: AppTheme.bodyLarge.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTheme.bodyMedium,
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppTheme.textLight,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

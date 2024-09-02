import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:mysql1/mysql1.dart';

class User {
  int user_id;
  String Fname;
  String Lname;
  String email;
  String username;
  String passwordHash;
  bool isAdmin;
  String? resetToken;
  User({
    required this.user_id,
    required this.Fname,
    required this.Lname,
    required this.email,
    required this.username,
    required String password,
    required this.isAdmin,
  }) : passwordHash = hashPassword(password);
  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }
  String generateResetToken() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    resetToken = base64Url.encode(values);
    return resetToken!;
  }
  bool verifyResetToken(String token) {
    return token == resetToken;
  }
  void resetPassword(String token, String newPassword) {
    if (verifyResetToken(token)) {
      passwordHash = hashPassword(newPassword);
      resetToken = null;
      print('=== Password reset successful. ===');
    } else {
      print('Invalid reset token.');
    }
  }
}
class UserManager {
  final MySqlConnection conn;
  UserManager(this.conn);
  Future<void> registerUser(int user_id, String Fname, String Lname, String email, String username, String password, bool isAdmin) async {
    var user = User(user_id: user_id, Fname: Fname, Lname: Lname, email: email, username: username, password: password, isAdmin: isAdmin);
    await conn.query(
      'INSERT INTO users (user_id, Fname, Lname, email, username, passwordHash, isAdmin) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [user.user_id, user.Fname, user.Lname, user.email, user.username, user.passwordHash, user.isAdmin ? 1 : 0],
    );
    print('=== Your account setup is now complete ===');
    print('=== Congratulations! Welcome to our platform. ===');
  }
  Future<void> loginUser(String email, String password) async {
    var results = await conn.query(
      'SELECT user_id, username, Fname, Lname, email, passwordHash, isAdmin FROM users WHERE email = ?',
      [email],
    );
    if (results.isEmpty) {
      print('??? User not found. ???');
      print('-- Program exits --');
      await conn.close();
      exit(0);
    }
    var row = results.first;
    var username = row['username'] as String;
    var passwordHash = row['passwordHash'] as String;
    bool isAdmin = (row['isAdmin'] as int) == 1;
    if (User.hashPassword(password) == passwordHash) {
      print('### You have successfully signed in. Welcome, $username! ###');
      print('--- Your Details ---');
      print('User ID: ${row['user_id']}');
      print('First Name: ${row['Fname']}');
      print('Last Name: ${row['Lname']}');
      print('Email: ${row['email']}');
      print('--- End of Details ---');
      if (isAdmin) {
        await showAdminDashboard();
      } else {
        await showUserCourses(row['user_id'] as int);
      }
    } else {
      print('??? Invalid password or username. ???');
      print('-- Program exits --');
      await conn.close();
      exit(0);
    }
  }
  Future<void> showUserCourses(int userId) async {
    var results = await conn.query(
      'SELECT course_name FROM user_courses WHERE user_id = ?',
      [userId],
    );
    if (results.isEmpty) {
      print('You have no courses enrolled.');
    } else {
      print('--- Your Courses ---');
      for (var row in results) {
        print('${row['course_name']}');
      }
      print('--- End of Courses ---');
    }
    print('=== Please choose a new course you are interested in: ===');
    print('1. Computer Science');
    print('2. Maintenance and Troubleshooting');
    var option = stdin.readLineSync();
    switch (option) {
      case '1':
        await applyForCourse(userId, 'Computer Science');
        await conn.close();
        exit(0);

      case '2':
        await applyForCourse(userId, 'Maintenance and Troubleshooting');
        await conn.close();
        exit(0);

      default:
        print('Invalid option. Please try again.');
        await showUserCourses(userId);
        await conn.close();
        exit(0);
    }
  }
  Future<void> applyForCourse(int userId, String courseName) async {
    await conn.query(
      'INSERT INTO user_courses (user_id, course_name) VALUES (?, ?)',
      [userId, courseName],
    );
    print('### You have successfully applied for the $courseName course. ###');
    await conn.close();
    exit(0);
  }
  Future<void> initiatePasswordReset(String email) async {
    var results = await conn.query(
      'SELECT username FROM users WHERE email = ?',
      [email],
    );
    if (results.isEmpty) {
      print('User not found. Please try again.');
      print('-- Program exits --');
      await conn.close();
      exit(0);
    }
    var user = User(
      user_id: 0,
      Fname: '',
      Lname: '',
      email: email,
      username: results.first['username'] as String,
      password: '',
      isAdmin: false,
    );
    var token = user.generateResetToken();
    await conn.query(
      'UPDATE users SET resetToken = ? WHERE email = ?',
      [token, email],
    );
    print('Password reset token generated: $token');
  }
  Future<void> completePasswordReset(String email, String token, String newPassword) async {
    var results = await conn.query(
      'SELECT resetToken FROM users WHERE email = ?',
      [email],
    );
    if (results.isEmpty) {
      print('User not found.');
      print('-- Program exits --');
      await conn.close();
      exit(0);
    }
    var storedToken = results.first['resetToken'] as String?;
    if (storedToken == token) {
      var newPasswordHash = User.hashPassword(newPassword);
      await conn.query(
        'UPDATE users SET passwordHash = ?, resetToken = NULL WHERE email = ?',
        [newPasswordHash, email],
      );
      print('Password reset successful.');
      await conn.close();
      exit(0);
    } else {
      print('Invalid reset token. Exiting the program.');
      await conn.close();
      exit(0);
    }
  }
  Future<void> showAdminDashboard() async {
    print('=== Admin Dashboard ===');
    // Add admin-specific functionality here
    print('--- End of Admin Dashboard ---');
  }
}
class Notification {
  int id;
  int userId;
  String message;
  DateTime date;
  Notification({
    required this.id,
    required this.userId,
    required this.message,
    required this.date,
  });
  static Notification fromRow(ResultRow row) {
    return Notification(
      id: row['id'] as int,
      userId: row['user_id'] as int,
      message: row['message'] as String,
      date: DateTime.parse(row['date'] as String),
    );
  }
}
class NotificationManager {
  final MySqlConnection conn;
  NotificationManager(this.conn);
  Future<void> fetchUserNotifications(int userId) async {
    var results = await conn.query(
      'SELECT id, user_id, message, date FROM notifications WHERE user_id = ?',
      [userId],
    );
    if (results.isEmpty) {
      print('No notifications for this user.');
    } else {
      print('--- Notifications ---');
      for (var row in results) {
        var notification = Notification.fromRow(row);
        print('ID: ${notification.id}');
        print('Message: ${notification.message}');
        print('Date: ${notification.date}');
        print('--- End of Notification ---');
      }
    }
  }
  Future<void> addNotification(int userId, String message) async {
    await conn.query(
      'INSERT INTO notifications (user_id, message, date) VALUES (?, ?, ?)',
      [userId, message, DateTime.now().toIso8601String()],
    );
    print('Notification added successfully.');
  }
}

void main() async {
  final settings = ConnectionSettings(
    host: 'localhost',
    port: 3306,
    user: 'root',
    db: 'user_reset',
  );
  final conn = await MySqlConnection.connect(settings);
  var userManager = UserManager(conn);
  var notificationManager = NotificationManager(conn);

  while (true) {
    print('=== Welcome to my system! Please choose an option. ===');
    print('1. Register');
    print('2. Login');
    print('3. Forgot Password');
    print('4. Exit');
    print('=== Select 1 for registration, 2 for login, 3 for password reset, and 4 to exit. ===');
    var option = stdin.readLineSync();
    switch (option) {

      case '1':
        print('Enter your user ID:');
        int user_id = int.parse(stdin.readLineSync()!);
        print('Enter your first name:');
        String Fname = stdin.readLineSync()!;
        print('Enter your last name:');
        String Lname = stdin.readLineSync()!;
        print('Enter your email:');
        String email = stdin.readLineSync()!;
        print('Enter your username:');
        String username = stdin.readLineSync()!;
        print('Enter your password:');
        stdin.echoMode = false;
        String password1 = stdin.readLineSync()!;
        stdin.echoMode = true;
        print('Verify your password:');
        stdin.echoMode = false;
        String password2 = stdin.readLineSync()!;
        stdin.echoMode = true;
        print('Are you an admin? (yes/no)');
        String isAdminInput = stdin.readLineSync()!;
        bool isAdmin = isAdminInput.toLowerCase() == 'yes';
        if (password1 == password2) {
          await userManager.registerUser(user_id, Fname, Lname, email, username, password1, isAdmin);
          print('=== Registration successful! ===');
        } else {
          print('Passwords do not match. Please try again.');
        }
         await conn.close();
        exit(0);

      case '2':
        print('Enter your email:');
        String email = stdin.readLineSync()!;
        print('Enter your password:');
        stdin.echoMode = false;
        String password = stdin.readLineSync()!;
        stdin.echoMode = true;
        await userManager.loginUser(email, password);
        await conn.close();
        exit(0);

      case '3':
        print('Enter your email:');
        String email = stdin.readLineSync()!;
        await userManager.initiatePasswordReset(email);
        print('Enter the reset token you received:');
        String token = stdin.readLineSync()!;
        print('Enter your new password:');
        stdin.echoMode = false;
        String newPassword = stdin.readLineSync()!;
        stdin.echoMode = true;
        await userManager.completePasswordReset(email, token, newPassword);
        await conn.close();
        exit(0);

      case '4':
        print('Exiting the program. Goodbye!');
        await conn.close();
        exit(0);
      default:
        print('Invalid option. Please try again.');
    }
  }
}
      
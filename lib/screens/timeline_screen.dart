import 'dart:io' as io;

import 'package:ambulantcollector/screens/dashboardvendor.dart';
import 'package:ambulantcollector/screens/signin_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';


class TimelineScreen extends StatefulWidget {
  final String userId;

  const TimelineScreen({super.key, required this.userId});

  @override
  _TimelineScreenState createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late Stream<DocumentSnapshot> _registrationStream;
  Map<int, List<XFile>> _selectedFiles = {}; // Map to track selected files per request
  String? _uploadErrorMessage;
  Map<String, bool> _submissionStatus = {};
  String? _declineReason; // Change to store a single decline reason  

  @override
  void initState() {
    super.initState();
    _registrationStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .snapshots();
    _loadSubmissionStatus();
    fetchDeclineReason();   }

// Assuming you're using a FutureBuilder or similar to fetch data
Future<void> fetchDeclineReason() async {
    DocumentSnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get(); // Make sure you get the right user document

    if (snapshot.exists) {
      setState(() {
        _declineReason = snapshot['decline_reason'] ?? ''; // Get the decline reason
      });
    }
  }


  Future<void> _loadSubmissionStatus() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();

    if (userDoc.exists) {
      final timeline = List<Map<String, dynamic>>.from(userDoc['timeline'] ?? []);
      for (var i = 0; i < timeline.length; i++) {
        if (timeline[i]['status'] == 'Request Info' ||
            timeline[i]['status'] == 'Additional Info Submitted') {
          _submissionStatus['issubmitted${i + 1}'] = timeline[i]['issubmitted${i + 1}'] ?? false;
          _selectedFiles[i + 1] = []; // Initialize empty file list for each request
        }
      }
    }
  }

  Future<void> _submitAdditionalInfo(String additionalInfo, int requestIndex) async {
    if (_selectedFiles[requestIndex] == null || _selectedFiles[requestIndex]!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select files to upload')),
      );
      return;
    }

     List<String> uploadedFileUrls = [];
     List<String> originalFileNames = []; // List to store original filenames

  try {
    for (var file in _selectedFiles[requestIndex]!) {
      String fileName = file.name;
      String filePath = 'uploads/${widget.userId}/$fileName';
      
      if (kIsWeb) {
        var bytes = await file.readAsBytes();
        var ref = firebase_storage.FirebaseStorage.instance.ref().child(filePath);
        var uploadTask = await ref.putData(bytes);
        var downloadUrl = await uploadTask.ref.getDownloadURL();
        uploadedFileUrls.add(downloadUrl); // Store only the file name
        originalFileNames.add(fileName); // Store the original filename

      } else {
        io.File fileToUpload = io.File(file.path);
        var uploadTask = await firebase_storage.FirebaseStorage.instance.ref(filePath).putFile(fileToUpload);
        String downloadUrl = await uploadTask.ref.getDownloadURL();
        uploadedFileUrls.add(downloadUrl); // Store only the file name
        originalFileNames.add(fileName); // Store the original filename

      }
    }


      final docRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);
      final userDoc = await docRef.get();
      final timeline = List<Map<String, dynamic>>.from(userDoc['timeline'] ?? []);
      final now = Timestamp.now();

      if (timeline.length > requestIndex - 1) {
        timeline[requestIndex - 1]['status'] = 'Additional Info Submitted';
        timeline[requestIndex - 1]['timestamp'] = now;
        timeline[requestIndex - 1]['issubmitted${requestIndex}'] = true; // Ensure correct index
        timeline[requestIndex - 1]['uploadedFiles'] = uploadedFileUrls; // Store URL
        timeline[requestIndex - 1]['originalFileNames'] = originalFileNames; // Store original filenames

      }

      await docRef.update({'timeline': timeline});

      setState(() {
        _selectedFiles[requestIndex] = [];
        _submissionStatus['issubmitted${requestIndex}'] = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Additional information submitted successfully')),
      );
    } catch (e) {
      setState(() {
        _uploadErrorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload files: $_uploadErrorMessage')),
      );
    }
  }

  Future<void> _pickFiles(int requestIndex) async {
    if (_submissionStatus['issubmitted${requestIndex}'] == true) return;

    final ImagePicker picker = ImagePicker();
    final List<XFile>? newFiles = await picker.pickMultiImage();

    if (newFiles != null) {
      setState(() {
        if (_selectedFiles[requestIndex] != null) {
          _selectedFiles[requestIndex]!.addAll(newFiles.where((newFile) =>
              !_selectedFiles[requestIndex]!.any((selectedFile) => selectedFile.name == newFile.name)));
        } else {
          _selectedFiles[requestIndex] = newFiles;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
       appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white), // Back icon with white color
            onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) =>const  SignInScreen()), // Navigate to Dashboard
            );
          }
        ),
          title: const Text(""), // Empty title to avoid spacing issues
          flexibleSpace: const Center( // Center the content
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, // Center the text and icon
              mainAxisSize: MainAxisSize.min, // Minimize the space taken by the Row
              children: [
                Icon(Icons.timelapse_sharp, color: Colors.white), // Icon next to the text
                SizedBox(width: 8), // Space between icon and text
                Text(
                  "Application Timeline",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20, // Set text color to white
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: const Color.fromARGB(255, 31, 232, 37), // Set background color to green
          elevation: 1.0,
        ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _registrationStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('No data available.'));
          }

          final registrationData = snapshot.data!.data() as Map<String, dynamic>?;
          if (registrationData == null) {
            return const Center(child: Text('No registration data available.'));
          }

          final currentStatus = registrationData['status'] ?? 'Unknown';
          final timeline = List<Map<String, dynamic>>.from(registrationData['timeline'] ?? []);

          // Retrieve approver's email and timestamp for approved status
          var approvedBy = registrationData['approved_by'] ?? '';
          var approvedAt = registrationData['approved_at']; // Retrieve timestamp

          DateTime? approvedDateTime;
          if (approvedAt != null && approvedAt is Timestamp) {
            approvedDateTime = approvedAt.toDate(); // Convert Firestore Timestamp to DateTime
          }


          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimelineStep(
                    context,
                    status: 'Registration',
                    isCompleted: true,
                    isCurrent: currentStatus == 'Pending Review' ||
                        currentStatus == 'Pending Approval' ||
                        currentStatus == 'Approved',
                  ),
                  _buildTimelineStep(
                    context,
                    status: 'Pending Review',
                    isCompleted: currentStatus != 'Registration',
                    isCurrent: currentStatus == 'Pending Review',
                  ),
                  ..._buildAdditionalInfoSteps(timeline),
                  _buildTimelineStep(
                    context,
                    status: 'Pending Approval',
                    isCompleted: currentStatus == 'Pending Approval' ||
                        currentStatus == 'Approved',
                    isCurrent: currentStatus == 'Pending Approval',
                  ),
                  _buildTimelineStep(
                    context,
                    status: 'Approved',
                    isCompleted: currentStatus == 'Approved',
                    isCurrent: currentStatus == 'Approved',
                  ),

                if (currentStatus == 'Declined') 
                  if (currentStatus == 'Declined') 
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align items at the start
                    children: [
                      const SizedBox(width: 10), // Space before the vertical line
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 2, // Width of the vertical line
                            height: 57, // Height to connect with the Approved step
                            color: Colors.red, // Line color
                          ),
                          const SizedBox(height: 5), // Space before the icon row
                          // Circle with X icon and Declined text
                          Row(
                            children: [
                              Transform.translate(
                                offset: const Offset(-5, -5), // Move the X icon to the left and up
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.red, // Circle color
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.clear, // X icon
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4), // Space between circle and text
                              Container(
                              padding: const EdgeInsets.only(bottom: 6), // Adjust the bottom padding to move it up
                              child: const Text(
                                'Declined',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ],
                          ),
                          const SizedBox(height: 10), // Space between icon/text and apology message
                          const Padding(
                            padding: EdgeInsets.only(left: 18.0), // Add space on the left
                            child: Text(
                              'I\'M SORRY YOUR APPLICATION \n HAS BEEN DECLINED!',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        const SizedBox(height: 10), // Space above the reason text
                          if (_declineReason != null && _declineReason!.isNotEmpty) // Only show if declineReason has a value
                            Padding(
                              padding: const EdgeInsets.only(left: 16.0), // Add left padding
                              child: Text(
                                'Reason: $_declineReason', // Display the decline reason
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),


                              if (currentStatus == 'Approved') 
                                  Padding(
                                    padding: const EdgeInsets.only(left: 20.0), // Adjust the left padding
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start, // Align children to the start
                                      children: [
                                        const SizedBox(height: 20),
                                        const Text(
                                          'CONGRATULATIONS YOUR \n APPLICATION IS APPROVED!!!',
                                          style: TextStyle(
                                            color: Color.fromARGB(255, 32, 222, 38),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.start, // Change to start for consistency
                                        ),
                                        const SizedBox(height: 8), // Add some space between texts
                                        Text(
                                          'Approved by: $approvedBy', 
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.normal,
                                          ),
                                          textAlign: TextAlign.start, // Change to start for consistency
                                        ),
                                        if (approvedDateTime != null) // Ensure approvedDateTime is not null
                                          Text(
                                            'Approved on: ${approvedDateTime.toLocal().toString().substring(0, 19)}', // Format the timestamp
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            textAlign: TextAlign.start, // Change to start for consistency
                                          ),
                                      ],
                                    ),
                                  ),
                                      const SizedBox(height: 30),
                                        if (currentStatus == 'Approved') 
                                          Padding(
                                            padding: const EdgeInsets.only(left: 20.0), // Adjust the left padding
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start, // Align children to the start
                                              children: [
                                                const SizedBox(height: 20),
                                                const Text(
                                                  'CONGRATULATIONS YOUR \n APPLICATION IS APPROVED!!!',
                                                  style: TextStyle(
                                                    color: Color.fromARGB(255, 32, 222, 38),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.start, // Change to start for consistency
                                                ),
                                                const SizedBox(height: 8), // Add some space between texts
                                                Text(
                                                  'Approved by: $approvedBy', 
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.normal,
                                                  ),
                                                  textAlign: TextAlign.start, // Change to start for consistency
                                                ),
                                                if (approvedDateTime != null) // Ensure approvedDateTime is not null
                                                  Text(
                                                    'Approved on: ${approvedDateTime.toLocal().toString().substring(0, 19)}', // Format the timestamp
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.normal,
                                                    ),
                                                    textAlign: TextAlign.start, // Change to start for consistency
                                                  ),
                                                const SizedBox(height: 30),
                                                if (currentStatus == "Approved") // Only display the button if the status is "Approved"
                                                  ElevatedButton(
                                                    onPressed: _goToDashboard,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color.fromARGB(255, 109, 237, 40), // Set the button color to green
                                                      foregroundColor: Colors.white, // Set the text color to white
                                                      minimumSize: const Size(200, 40), // Set a fixed width of 200 pixels
                                                      padding: const EdgeInsets.symmetric(vertical: 8), // Adjust vertical padding if needed
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8), // Set the roundness of the edges
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Go to Dashboard',
                                                      style: TextStyle(
                                                        fontSize: 16, // Adjust font size as needed
                                                        fontWeight: FontWeight.bold, // Make the text bold
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ]
                                      ),
                                   )
                                );
                             },
                          ),
                        );
                      }

List<Widget> _buildAdditionalInfoSteps(List<Map<String, dynamic>> timeline) {
  List<Widget> steps = [];

  for (var i = 0; i < timeline.length; i++) {
    final entry = timeline[i];
    if (entry['status'] == 'Request Info' || entry['status'] == 'Additional Info Submitted') {
      bool isSubmitted = entry['issubmitted${i + 1}'] ?? false;
      steps.add(
        _buildTimelineStep(
          context,
          status: 'Request Info - ${i + 1}',
          isCompleted: isSubmitted,
          isCurrent: !isSubmitted,
          child: _buildAdditionalInfoSection(timeline, i + 1),
        ),
      );
    }
  }

  return steps;
}

void launchEmail(String email) async {
  final Uri emailLaunchUri = Uri(
    scheme: 'mailto',
    path: email,
    query: 'subject=Your Subject&body=Your Message', // You can customize the subject and body
  );

  // Check if the device can launch the email
  if (await canLaunch(emailLaunchUri.toString())) {
    await launch(emailLaunchUri.toString());
  } else {
    throw 'Could not launch $emailLaunchUri';
  }
}


  Widget _buildTimelineStep(BuildContext context,
    {required String status,
    required bool isCompleted,
    required bool isCurrent,
    Widget? child}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : Icons.access_time,
                color: isCompleted ? const Color.fromARGB(255, 99, 217, 45) : Colors.grey,
              ),
              if (status != 'Approved')
                Container(
                  width: 2,
                  height: 50,
                  color: isCompleted ? const Color.fromARGB(255, 76, 210, 52) : Colors.grey,
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCurrent ?  Colors.black : Colors.black,
              ),
            ),
          ),
        ],
      ),
      if (child != null) child,
    ],
  );
}

Widget _buildAdditionalInfoSection(List<Map<String, dynamic>> timeline, int requestIndex) {
  final additionalInfoRequest = timeline[requestIndex - 1];
  String message = additionalInfoRequest['message'] ?? 'Please provide the requested information.';
  List<String>? originalFileNames = List<String>.from(additionalInfoRequest['originalFileNames'] ?? []); // Get original filenames
  bool isSubmitted = additionalInfoRequest['issubmitted${requestIndex}'] ?? false;

  // Extract requested_by and timestamp
  String requestedBy = additionalInfoRequest['requested_by'] ?? 'Unknown';
  DateTime timestamp = (additionalInfoRequest['timestamp'] as Timestamp).toDate();
  String formattedTimestamp = '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute}';


  return Padding(
    padding: const EdgeInsets.only(left: 30.0), // Adjust this value to match the line's position
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            //message
         RichText(
          text: TextSpan(
            children: [
              const TextSpan(
                text: 'You are requested to upload:\n ',
              ),
              TextSpan(
                text: message,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), // Bold weight for the message
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      RichText(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'Requested By: ',
            style: TextStyle(fontSize: 12), 
          ),
          TextSpan(
            text: requestedBy,
            style: const TextStyle(
              color: Colors.blue, // Set the color to blue
              fontWeight: FontWeight.normal,
              fontSize: 12,
              decoration: TextDecoration.underline, // Underline the text
            ),
            recognizer: TapGestureRecognizer()..onTap = () {
              // This code will execute when the email is tapped
              launchEmail(requestedBy); // Call a method to launch the email client
            },
          ),
        ],
      ),
    ),

        // Date Requested (Bold the label)
        RichText(
          text: TextSpan(
            children: [
              const TextSpan(
                text: 'Date Requested: ',
                style: TextStyle(fontSize: 12), // Bold the label
              ),
              TextSpan(
                text: formattedTimestamp, // Keep the value normal
                style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12), 

         // Optionally display orig filename
        if (originalFileNames.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: originalFileNames.map((fileName) => Text('File Uploaded: $fileName')).toList(),
          ),
        const SizedBox(height: 5), 
        // Selected Files
        if (_selectedFiles[requestIndex] != null && _selectedFiles[requestIndex]!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selected Files (${_selectedFiles[requestIndex]!.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              ..._selectedFiles[requestIndex]!.map((file) => Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name, // Use the original file name
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedFiles[requestIndex]!.removeWhere((selectedFile) => selectedFile.name == file.name);
                      });
                    },
                  ),
                ],
              )),
            ],
          ),
        const SizedBox(height: 10),
/*         // Uploaded Files
        if (uploadedFiles.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: uploadedFiles
                .map((fileName) => Text(
                      '- $fileName',
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ))
                .toList(),
          ), */
        const SizedBox(height: 10),
        // Upload Files Button
        GestureDetector(
          onTap: isSubmitted ? null : () => _pickFiles(requestIndex),
          child: Text(
            'Upload Files',
            style: TextStyle(
              color: isSubmitted ? Colors.grey : Colors.blue,
              decoration: isSubmitted ? TextDecoration.none : TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 10),
    // Submit Button
    ElevatedButton(
      onPressed: isSubmitted
          ? null
          : () {
              if (_selectedFiles[requestIndex] == null || _selectedFiles[requestIndex]!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select files to upload')),
                );
                return;
              }
              _submitAdditionalInfo(message, requestIndex);
            },
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 94, 212, 34), // Set the button color to green
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0), // Adjust this value for slight rounding
              ),
            ),
              child: const Text(
                'Submit',
                style: TextStyle(
                  color: Colors.white, // Set text color to white
                )
              )
            )
          ]
        )
      );
    }

   void _goToDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DashboardVendor()),
    );
  }
}


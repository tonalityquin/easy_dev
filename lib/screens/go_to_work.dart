import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/user/user_state.dart';

class GoToWork extends StatefulWidget {
  const GoToWork({super.key});

  @override
  State<GoToWork> createState() => _GoToWorkState();
}

class _GoToWorkState extends State<GoToWork> {
  bool _isLoading = false;

  void _handleWorkStatus(BuildContext context, UserState userState) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await userState.isHeWorking(); // 상태 전환 (출근/퇴근 처리)
      if (userState.isWorking && mounted) {
        Navigator.pushReplacementNamed(context, '/type_page');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildWorkButton(UserState userState) {
    final isWorking = userState.isWorking;
    final label = isWorking ? '퇴근하기' : '출근하기';
    final icon = isWorking ? Icons.logout : Icons.login;
    final colors = isWorking
        ? [Colors.redAccent, Colors.deepOrange]
        : [Colors.green.shade400, Colors.teal];

    return InkWell(
      onTap: _isLoading ? null : () => _handleWorkStatus(context, userState),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 55,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          )
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/type_page');
            });
          }

          return SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 96),
                      SizedBox(
                        height: 120,
                        child: Image.asset('assets/images/belivus_logo.PNG'),
                      ),
                      const SizedBox(height: 96),

                      Text(
                        '출근 전 사용자 정보 확인',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),

                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoRow('이름', userState.name),
                              _infoRow('전화번호', userState.phone),
                              _infoRow('역할', userState.role),
                              _infoRow('지역', userState.area),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                      _buildWorkButton(userState),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

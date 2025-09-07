import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../routes.dart'; // ← 추가: 라우트 사용

class ParkingPage extends StatelessWidget {
  const ParkingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text(
          '주차 관제 시스템',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
        actionsIconTheme: IconThemeData(color: cs.onSurface),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white,
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ParkingCardButton(
                icon: Icons.directions_car_filled_rounded,
                title: '차량 등록',
                subtitle: '번호판 등록 및 정보 관리',
                onTap: () {
                  // TODO: 차량 등록 화면 라우팅
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('차량 등록 화면으로 이동합니다. (구현 필요)')),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ParkingCardButton(
                icon: Icons.swap_vert_rounded,
                title: '입출차 기록',
                subtitle: '실시간 입출차 내역 조회',
                onTap: () {
                  // TODO: 로그 화면 라우팅
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('입출차 기록 화면으로 이동합니다. (구현 필요)')),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ParkingCardButton(
                icon: Icons.settings_applications_rounded,
                title: '설정',
                subtitle: '요금/권한/알림 설정',
                onTap: () {
                  // TODO: 설정 화면 라우팅
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('설정 화면으로 이동합니다. (구현 필요)')),
                  );
                },
              ),
            ],
          ),
        ),
      ),

      // ▼ 바텀 펠리컨 이미지 (탭하면 선택화면으로 이동)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.selector,
                  (route) => false, // 스택 정리 후 이동
            ),
            borderRadius: BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 120,
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParkingCardButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ParkingCardButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: cs.primary,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}

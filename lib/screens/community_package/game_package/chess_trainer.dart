// lib/screens/stub_package/game_package/chess_trainer.dart
// 입문자용 체스 학습 게임 (Flutter, 단일 파일)
// - 요청 반영: 말 탭 이동 제거 → "자판 입력(좌표)"으로만 이동
//   · 하단(백/흑 차례 안내 바로 아래)에 [선택칸][목표칸][실행][취소] 입력 바 추가
//   · 각 입력칸은 알파벳 1글자(a-h) + 숫자 1글자(1-8) 순서만 허용 (키패드 활성화)
//   · 키패드(소프트 키보드)가 뜨면 입력 바가 같이 위로 올라오도록 AnimatedPadding 적용
//   · '취소' 누르면 두 필드 모두 비우고 '선택' 필드로 포커스 이동
// - 레이아웃 수정: 키보드 표시 시 보드+상태바 높이 초과로 인한 오버플로우 방지
//   · 보드 한 변의 길이 = min(가로폭, 가용세로높이 - 상태바여유)
//   · 상태바여유는 안전하게 120px로 확보(필요하면 조정 가능)
// - 학습 흐름 개선: 사용자는 자기 진영만 입력 가능, 입력이 성공하면 코치(AI)가 자동으로 응수
//   · 코치 차례에는 입력칸 읽기전용 + “코치가 두는 중/코치 차례” 안내
//   · 연습판(tab=3)만 양쪽 조작 허용

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChessTrainerPage extends StatefulWidget {
  const ChessTrainerPage({super.key});
  @override
  State<ChessTrainerPage> createState() => _ChessTrainerPageState();
}

/* ─────────────────────────────────────────────────────────────────────────────
   기초 모델
   ───────────────────────────────────────────────────────────────────────────── */

enum Side { white, black }

enum PieceType { king, queen, rook, bishop, knight, pawn }

class Piece {
  final Side side;
  final PieceType type;
  const Piece(this.side, this.type);

  String get glyph => switch ((side, type)) {
    (Side.white, PieceType.king) => '♔',
    (Side.white, PieceType.queen) => '♕',
    (Side.white, PieceType.rook) => '♖',
    (Side.white, PieceType.bishop) => '♗',
    (Side.white, PieceType.knight) => '♘',
    (Side.white, PieceType.pawn) => '♙',
    (Side.black, PieceType.king) => '♚',
    (Side.black, PieceType.queen) => '♛',
    (Side.black, PieceType.rook) => '♜',
    (Side.black, PieceType.bishop) => '♝',
    (Side.black, PieceType.knight) => '♞',
    (Side.black, PieceType.pawn) => '♟',
  };
}

@immutable
class Move {
  final int from;
  final int to;
  final PieceType? promotion; // 폰만 사용
  final bool isCastleKingSide;
  final bool isCastleQueenSide;
  final bool isEnPassant;
  final bool isCapture;
  const Move({
    required this.from,
    required this.to,
    this.promotion,
    this.isCastleKingSide = false,
    this.isCastleQueenSide = false,
    this.isEnPassant = false,
    this.isCapture = false,
  });
}

// 보드 인덱싱: 0..63, a8=0, h8=7, a1=56, h1=63 (row-major)
class BoardPos {
  static int file(int sq) => sq % 8; // 0=a .. 7=h
  static int rank(int sq) => sq ~/ 8; // 0=8줄, 7=1줄
  static bool onBoard(int r, int f) => r >= 0 && r < 8 && f >= 0 && f < 8;
  static int rf(int r, int f) => r * 8 + f;
  static String algebraic(int sq) =>
      String.fromCharCode('a'.codeUnitAt(0) + file(sq)) + (8 - rank(sq)).toString();
}

class Position {
  final List<Piece?> board; // 길이 64
  Side stm; // side to move
  bool wkCastle;
  bool wqCastle;
  bool bkCastle;
  bool bqCastle; // 캐슬 권리
  int? epFile; // 앙파상 파일(0..7) 또는 null
  int halfmoveClock;
  int fullmoveNumber;

  Position._(this.board, this.stm, this.wkCastle, this.wqCastle, this.bkCastle,
      this.bqCastle, this.epFile, this.halfmoveClock, this.fullmoveNumber);

  factory Position.start() => Position.fromFEN(_startFEN);

  Position clone() => Position._([...board], stm, wkCastle, wqCastle, bkCastle,
      bqCastle, epFile, halfmoveClock, fullmoveNumber);

  static Position fromFEN(String fen) {
    final parts = fen.split(' ');
    final rows = parts[0].split('/');
    final b = List<Piece?>.filled(64, null);
    for (int r = 0; r < 8; r++) {
      int f = 0;
      for (final ch in rows[r].split('')) {
        if (int.tryParse(ch) != null) {
          f += int.parse(ch);
        } else {
          final side = ch == ch.toLowerCase() ? Side.black : Side.white;
          final type = switch (ch.toLowerCase()) {
            'k' => PieceType.king,
            'q' => PieceType.queen,
            'r' => PieceType.rook,
            'b' => PieceType.bishop,
            'n' => PieceType.knight,
            'p' => PieceType.pawn,
            _ => PieceType.pawn,
          };
          b[BoardPos.rf(r, f)] = Piece(side, type);
          f++;
        }
      }
    }
    final stm = parts[1] == 'w' ? Side.white : Side.black;
    final cast = parts[2];
    final wk = cast.contains('K');
    final wq = cast.contains('Q');
    final bk = cast.contains('k');
    final bq = cast.contains('q');
    final ep =
    parts[3] != '-' ? (parts[3][0].codeUnitAt(0) - 'a'.codeUnitAt(0)) : null;
    final hm = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    final fm = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
    return Position._(b, stm, wk, wq, bk, bq, ep, hm, fm);
  }

  String toFEN() {
    final rows = <String>[];
    for (int r = 0; r < 8; r++) {
      int empty = 0;
      final sb = StringBuffer();
      for (int f = 0; f < 8; f++) {
        final p = board[BoardPos.rf(r, f)];
        if (p == null) {
          empty++;
          continue;
        }
        if (empty > 0) {
          sb.write(empty);
          empty = 0;
        }
        final ch = switch (p.type) {
          PieceType.king => 'k',
          PieceType.queen => 'q',
          PieceType.rook => 'r',
          PieceType.bishop => 'b',
          PieceType.knight => 'n',
          PieceType.pawn => 'p',
        };
        sb.write(p.side == Side.white ? ch.toUpperCase() : ch);
      }
      if (empty > 0) sb.write(empty);
      rows.add(sb.toString());
    }
    final c = [
      if (wkCastle) 'K' else '',
      if (wqCastle) 'Q' else '',
      if (bkCastle) 'k' else '',
      if (bqCastle) 'q' else ''
    ].join();
    final cast = c.isEmpty ? '-' : c;
    final ep = epFile != null
        ? String.fromCharCode('a'.codeUnitAt(0) + epFile!) +
        (stm == Side.white ? '6' : '3')
        : '-';
    return '${rows.join('/')} ${stm == Side.white ? 'w' : 'b'} $cast $ep $halfmoveClock $fullmoveNumber';
  }
}

const _startFEN =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/* ─────────────────────────────────────────────────────────────────────────────
   합법 수 생성 (핀/체크 고려)
   ───────────────────────────────────────────────────────────────────────────── */

class MoveGen {
  static List<Move> legalMoves(Position pos) {
    final moves = <Move>[];
    for (int sq = 0; sq < 64; sq++) {
      final p = pos.board[sq];
      if (p == null || p.side != pos.stm) continue;
      switch (p.type) {
        case PieceType.pawn:
          _pawnMoves(pos, sq, moves);
        case PieceType.knight:
          _knightMoves(pos, sq, moves);
        case PieceType.bishop:
          _slideMoves(pos, sq, moves, const [(-1, -1), (1, -1), (-1, 1), (1, 1)]);
        case PieceType.rook:
          _slideMoves(pos, sq, moves, const [(1, 0), (-1, 0), (0, 1), (0, -1)]);
        case PieceType.queen:
          _slideMoves(pos, sq, moves, const [
            (-1, -1),
            (1, -1),
            (-1, 1),
            (1, 1),
            (1, 0),
            (-1, 0),
            (0, 1),
            (0, -1)
          ]);
        case PieceType.king:
          _kingMoves(pos, sq, moves);
      }
    }
    // 체크 걸린 수 제거(킹 노출 금지)
    return moves.where((m) => _makesLegal(pos, m)).toList();
  }

  static bool _makesLegal(Position pos, Move m) {
    final next = Engine.applyMove(pos, m);
    if (next == null) return false;
    return !Attack.isKingInCheck(next, pos.stm); // 이전 내킹이 체크면 불가
    // (next.stm = 상대 차례) → 내 킹이 체크면 방금 수는 불법
  }

  static void _addIfTarget(Position pos, int from, int r, int f, List<Move> out,
      {bool captureOnly = false, bool quietOnly = false}) {
    if (!BoardPos.onBoard(r, f)) return;
    final to = BoardPos.rf(r, f);
    final me = pos.board[from]!;
    final t = pos.board[to];
    if (t == null) {
      if (!captureOnly) out.add(Move(from: from, to: to));
    } else if (t.side != me.side) {
      if (!quietOnly) out.add(Move(from: from, to: to, isCapture: true));
    }
  }

  static void _slideMoves(
      Position pos, int from, List<Move> out, List<(int, int)> dirs) {
    final r0 = BoardPos.rank(from), f0 = BoardPos.file(from);
    final me = pos.board[from]!;
    for (final (dr, df) in dirs) {
      int r = r0 + dr, f = f0 + df;
      while (BoardPos.onBoard(r, f)) {
        final to = BoardPos.rf(r, f);
        final t = pos.board[to];
        if (t == null) {
          out.add(Move(from: from, to: to));
        } else {
          if (t.side != me.side) {
            out.add(Move(from: from, to: to, isCapture: true));
          }
          break;
        }
        r += dr;
        f += df;
      }
    }
  }

  static void _knightMoves(Position pos, int from, List<Move> out) {
    final r = BoardPos.rank(from), f = BoardPos.file(from);
    for (final (dr, df) in const [
      (-2, -1),
      (-2, 1),
      (-1, -2),
      (-1, 2),
      (1, -2),
      (1, 2),
      (2, -1),
      (2, 1)
    ]) {
      _addIfTarget(pos, from, r + dr, f + df, out);
    }
  }

  static void _pawnMoves(Position pos, int from, List<Move> out) {
    final p = pos.board[from]!;
    final dir = p.side == Side.white ? -1 : 1;
    final r = BoardPos.rank(from), f = BoardPos.file(from);

    // 전진 1
    final r1 = r + dir;
    if (BoardPos.onBoard(r1, f) && pos.board[BoardPos.rf(r1, f)] == null) {
      _addPawnAdvance(pos, from, BoardPos.rf(r1, f), out);
      // 전진 2(초기 위치)
      final startRank = p.side == Side.white ? 6 : 1;
      final r2 = r + 2 * dir;
      if (r == startRank && pos.board[BoardPos.rf(r2, f)] == null) {
        out.add(Move(from: from, to: BoardPos.rf(r2, f)));
      }
    }
    // 대각 캡처
    for (final df in const [-1, 1]) {
      final rf = (r + dir, f + df);
      if (!BoardPos.onBoard(rf.$1, rf.$2)) continue;
      final to = BoardPos.rf(rf.$1, rf.$2);
      final t = pos.board[to];
      if (t != null && t.side != p.side) {
        _addPawnAdvance(pos, from, to, out, capture: true);
      }
    }
    // 앙파상
    if (pos.epFile != null) {
      final targetF = pos.epFile!;
      if ((f - targetF).abs() == 1) {
        final epRank = p.side == Side.white ? 2 : 5;
        if (r + dir == epRank) {
          final to = BoardPos.rf(epRank, targetF);
          out.add(Move(from: from, to: to, isEnPassant: true, isCapture: true));
        }
      }
    }
  }

  static void _addPawnAdvance(Position pos, int from, int to, List<Move> out,
      {bool capture = false}) {
    final endRank = BoardPos.rank(to);
    final me = pos.board[from]!;
    final promoRank = me.side == Side.white ? 0 : 7;
    if (endRank == promoRank) {
      for (final pt in const [
        PieceType.queen,
        PieceType.rook,
        PieceType.bishop,
        PieceType.knight
      ]) {
        out.add(Move(from: from, to: to, promotion: pt, isCapture: capture));
      }
    } else {
      out.add(Move(from: from, to: to, isCapture: capture));
    }
  }

  static void _kingMoves(Position pos, int from, List<Move> out) {
    final r = BoardPos.rank(from), f = BoardPos.file(from);
    for (final (dr, df) in const [
      (-1, -1),
      (-1, 0),
      (-1, 1),
      (0, -1),
      (0, 1),
      (1, -1),
      (1, 0),
      (1, 1)
    ]) {
      _addIfTarget(pos, from, r + dr, f + df, out);
    }
    // 캐슬링
    final side = pos.board[from]!.side;
    if (Attack.isSquareAttacked(
        pos, from, side == Side.white ? Side.black : Side.white)) {
      return; // 체크 중엔 불가
    }

    if (side == Side.white) {
      // e1(60) 기준
      if (pos.wkCastle && pos.board[61] == null && pos.board[62] == null) {
        if (!Attack.isSquareAttacked(pos, 61, Side.black) &&
            !Attack.isSquareAttacked(pos, 62, Side.black)) {
          out.add(const Move(from: 60, to: 62, isCastleKingSide: true));
        }
      }
      if (pos.wqCastle &&
          pos.board[59] == null &&
          pos.board[58] == null &&
          pos.board[57] == null) {
        if (!Attack.isSquareAttacked(pos, 59, Side.black) &&
            !Attack.isSquareAttacked(pos, 58, Side.black)) {
          out.add(const Move(from: 60, to: 58, isCastleQueenSide: true));
        }
      }
    } else {
      // e8(4) 기준
      if (pos.bkCastle && pos.board[5] == null && pos.board[6] == null) {
        if (!Attack.isSquareAttacked(pos, 5, Side.white) &&
            !Attack.isSquareAttacked(pos, 6, Side.white)) {
          out.add(const Move(from: 4, to: 6, isCastleKingSide: true));
        }
      }
      if (pos.bqCastle &&
          pos.board[3] == null &&
          pos.board[2] == null &&
          pos.board[1] == null) {
        if (!Attack.isSquareAttacked(pos, 3, Side.white) &&
            !Attack.isSquareAttacked(pos, 2, Side.white)) {
          out.add(const Move(from: 4, to: 2, isCastleQueenSide: true));
        }
      }
    }
  }
}

class Attack {
  static bool isKingInCheck(Position pos, Side side) {
    int kingSq = -1;
    for (int i = 0; i < 64; i++) {
      final p = pos.board[i];
      if (p != null && p.side == side && p.type == PieceType.king) {
        kingSq = i;
        break;
      }
    }
    if (kingSq == -1) return false;
    final opp = side == Side.white ? Side.black : Side.white;
    return isSquareAttacked(pos, kingSq, opp);
  }

  static bool isSquareAttacked(Position pos, int sq, Side bySide) {
    final r = BoardPos.rank(sq), f = BoardPos.file(sq);
    // 나이트
    for (final (dr, df) in const [
      (-2, -1),
      (-2, 1),
      (-1, -2),
      (-1, 2),
      (1, -2),
      (1, 2),
      (2, -1),
      (2, 1)
    ]) {
      final rr = r + dr, ff = f + df;
      if (!BoardPos.onBoard(rr, ff)) continue;
      final p = pos.board[BoardPos.rf(rr, ff)];
      if (p != null && p.side == bySide && p.type == PieceType.knight) {
        return true;
      }
    }
    // 폰
    final dir = bySide == Side.white ? -1 : 1;
    for (final df in const [-1, 1]) {
      final rr = r + dir, ff = f + df;
      if (!BoardPos.onBoard(rr, ff)) continue;
      final p = pos.board[BoardPos.rf(rr, ff)];
      if (p != null && p.side == bySide && p.type == PieceType.pawn) {
        return true;
      }
    }
    // 킹(접근 1칸)
    for (final (dr, df) in const [
      (-1, -1),
      (-1, 0),
      (-1, 1),
      (0, -1),
      (0, 1),
      (1, -1),
      (1, 0),
      (1, 1)
    ]) {
      final rr = r + dr, ff = f + df;
      if (!BoardPos.onBoard(rr, ff)) continue;
      final p = pos.board[BoardPos.rf(rr, ff)];
      if (p != null && p.side == bySide && p.type == PieceType.king) {
        return true;
      }
    }
    // 비숍/퀸 대각
    for (final (dr, df) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      int rr = r + dr, ff = f + df;
      while (BoardPos.onBoard(rr, ff)) {
        final p = pos.board[BoardPos.rf(rr, ff)];
        if (p != null) {
          if (p.side == bySide &&
              (p.type == PieceType.bishop || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        rr += dr;
        ff += df;
      }
    }
    // 룩/퀸 직선
    for (final (dr, df) in const [
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1)
    ]) {
      int rr = r + dr, ff = f + df;
      while (BoardPos.onBoard(rr, ff)) {
        final p = pos.board[BoardPos.rf(rr, ff)];
        if (p != null) {
          if (p.side == bySide &&
              (p.type == PieceType.rook || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        rr += dr;
        ff += df;
      }
    }
    return false;
  }
}

/* ─────────────────────────────────────────────────────────────────────────────
   적용/되돌리기 & 평가/간단 AI
   ───────────────────────────────────────────────────────────────────────────── */

class Engine {
  static Position? applyMove(Position pos, Move m) {
    final next = pos.clone();
    final me = next.stm;
    final opp = me == Side.white ? Side.black : Side.white;
    final piece = next.board[m.from];
    if (piece == null) return null;

    // 앙파상 캡처 제거
    if (m.isEnPassant) {
      final toR = BoardPos.rank(m.to);
      final toF = BoardPos.file(m.to);
      final capR = me == Side.white ? toR + 1 : toR - 1;
      final capSq = BoardPos.rf(capR, toF);
      next.board[capSq] = null;
    }

    // 이동/캡처
    final captured = next.board[m.to];
    next.board[m.to] = piece;
    next.board[m.from] = null;

    // 폰 프로모션
    if (piece.type == PieceType.pawn && m.promotion != null) {
      next.board[m.to] = Piece(me, m.promotion!);
    }

    // 캐슬링 룩 이동
    if (piece.type == PieceType.king) {
      if (me == Side.white) {
        next.wkCastle = false;
        next.wqCastle = false;
      } else {
        next.bkCastle = false;
        next.bqCastle = false;
      }
      if (m.isCastleKingSide) {
        if (me == Side.white) {
          next.board[63] = null;
          next.board[61] = Piece(Side.white, PieceType.rook);
        } else {
          next.board[7] = null;
          next.board[5] = Piece(Side.black, PieceType.rook);
        }
      }
      if (m.isCastleQueenSide) {
        if (me == Side.white) {
          next.board[56] = null;
          next.board[59] = Piece(Side.white, PieceType.rook);
        } else {
          next.board[0] = null;
          next.board[3] = Piece(Side.black, PieceType.rook);
        }
      }
    }

    // 룩 이동/캡처 시 캐슬 권리 박탈
    void revokeCastlingByRook(int sq) {
      switch (sq) {
        case 63:
          next.wkCastle = false; // h1
          break;
        case 56:
          next.wqCastle = false; // a1
          break;
        case 7:
          next.bkCastle = false; // h8
          break;
        case 0:
          next.bqCastle = false; // a8
          break;
      }
    }

    if (piece.type == PieceType.rook) revokeCastlingByRook(m.from);
    if (captured != null && captured.type == PieceType.rook) {
      revokeCastlingByRook(m.to);
    }

    // 앙파상 대상 파일 설정
    next.epFile = null;
    if (piece.type == PieceType.pawn) {
      final fromR = BoardPos.rank(m.from);
      final toR = BoardPos.rank(m.to);
      if ((fromR - toR).abs() == 2) next.epFile = BoardPos.file(m.to);
    }

    // halfmove/fullmove 업데이트
    next.halfmoveClock =
    (piece.type == PieceType.pawn || m.isCapture) ? 0 : pos.halfmoveClock + 1;
    next.fullmoveNumber =
    me == Side.black ? pos.fullmoveNumber + 1 : pos.fullmoveNumber;

    // 턴 교대
    next.stm = opp;

    return next;
  }

  // 간단 평가(머터리얼 + 활동성): 백 관점 점수
  static int evaluate(Position pos) {
    int score = 0;
    for (int i = 0; i < 64; i++) {
      final p = pos.board[i];
      if (p == null) continue;
      final v = switch (p.type) {
        PieceType.king => 0,
        PieceType.queen => 900,
        PieceType.rook => 500,
        PieceType.bishop => 330,
        PieceType.knight => 320,
        PieceType.pawn => 100,
      };
      score += p.side == Side.white ? v : -v;
    }
    final myMoves = MoveGen.legalMoves(pos).length;
    final clone = pos.clone()..stm = (pos.stm == Side.white ? Side.black : Side.white);
    final oppMoves = MoveGen.legalMoves(clone).length;
    score += (myMoves - oppMoves) * 2;
    return score;
  }

  // 2-ply 탐색(가벼움). stm 관점에서 최선 수
  static Move? pickMove(Position pos) {
    final moves = MoveGen.legalMoves(pos);
    if (moves.isEmpty) return null;
    final me = pos.stm;
    Move? best; int bestScore = -9999999;
    for (final m in moves) {
      final next = applyMove(pos, m);
      if (next == null) continue;
      final valNext = _evalFor(next, me);
      final reply = MoveGen.legalMoves(next);
      int worstForMe = 9999999;
      if (reply.isEmpty) {
        worstForMe = valNext + 10000;
      } else {
        for (final r in reply) {
          final nn = applyMove(next, r);
          if (nn == null) continue;
          final v = _evalFor(nn, me);
          if (v < worstForMe) worstForMe = v;
        }
      }
      if (worstForMe > bestScore) { bestScore = worstForMe; best = m; }
    }
    return best;
  }

  static Position _ensureSide(Position pos, Side asSide) {
    if (pos.stm == asSide) return pos;
    final p = pos.clone()..stm = asSide;
    return p;
  }

  static int _evalFor(Position pos, Side perspective) {
    final whiteScore = evaluate(_ensureSide(pos, Side.white));
    return perspective == Side.white ? whiteScore : -whiteScore;
  }
}

/* ─────────────────────────────────────────────────────────────────────────────
   레슨/퍼즐 정의 (간단 예시)
   ───────────────────────────────────────────────────────────────────────────── */

class Lesson {
  final String title;
  final String description;
  final String fen;
  final String goal;
  final bool Function(Position, List<MoveRecord>) isCleared;
  const Lesson({
    required this.title,
    required this.description,
    required this.fen,
    required this.goal,
    required this.isCleared,
  });
}

class Puzzle {
  final String title;
  final String fen;
  final Side toMove;
  final String hint;
  final bool Function(Position, List<MoveRecord>) isSolved;
  const Puzzle(
      {required this.title,
        required this.fen,
        required this.toMove,
        required this.hint,
        required this.isSolved});
}

class MoveRecord {
  final Move m;
  final Piece? captured;
  MoveRecord(this.m, this.captured);
}

final lessons = <Lesson>[
  Lesson(
    title: '룩의 길을 열자',
    description: '룩(차)은 가로/세로로 멀리 이동합니다. 룩으로 상대 폰을 잡아보세요.',
    fen: '8/8/8/8/8/8/3p4/R6K w - - 0 1',
    goal: '백이 1수 안에 d2의 폰을 캡처',
    isCleared: (pos, history) {
      if (history.isEmpty) return false;
      final h = history.last;
      final to = h.m.to;
      final cap = h.captured;
      return to == 51 /*d2*/ &&
          cap != null &&
          cap.type == PieceType.pawn &&
          cap.side == Side.black;
    },
  ),
  Lesson(
    title: '나이트의 점프',
    description: '나이트(마)는 점프해서 이동합니다. 나이트로 중앙에 도달하세요.',
    fen: '8/8/8/8/8/8/8/N6K w - - 0 1',
    goal: 'a1의 나이트를 c2(62) 또는 b3(49)에 배치',
    isCleared: (pos, history) {
      if (history.isEmpty) return false;
      final to = history.last.m.to;
      return to == 62 || to == 49; // c2 or b3
    },
  ),
];

final puzzles = <Puzzle>[
  Puzzle(
    title: 'Mate in 1 (백차례)',
    fen: '6k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1',
    toMove: Side.white,
    hint: '킹을 모서리에 가둔 뒤 체크메이트를 노려보세요.',
    isSolved: (pos, history) {
      if (history.isEmpty) return false;
      final sideMoved = history.length.isOdd ? Side.white : Side.black;
      if (sideMoved != Side.white) return false;
      return Attack.isKingInCheck(pos, Side.black);
    },
  ),
  Puzzle(
    title: '캐슬링을 경험해보자 (백차례)',
    fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
    toMove: Side.white,
    hint: '캐슬링을 시도해 보세요.',
    isSolved: (pos, history) {
      if (history.isEmpty) return false;
      final m = history.last.m;
      return m.isCastleKingSide || m.isCastleQueenSide;
    },
  ),
];

/* ─────────────────────────────────────────────────────────────────────────────
   입력 포맷터: a-h + 1-8 (순서 고정, 최대 2글자)
   ───────────────────────────────────────────────────────────────────────────── */

class SquareTextFormatter extends TextInputFormatter {
  static final _letter = RegExp(r'[a-hA-H]');
  static final _digit = RegExp(r'[1-8]');
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final src = newValue.text.toLowerCase();
    String out = '';
    for (int i = 0; i < src.length && out.length < 2; i++) {
      final ch = src[i];
      if (out.isEmpty) {
        if (_letter.hasMatch(ch)) out += ch;
      } else if (out.length == 1) {
        if (_digit.hasMatch(ch)) out += ch;
      }
    }
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/* ─────────────────────────────────────────────────────────────────────────────
   화면
   ───────────────────────────────────────────────────────────────────────────── */

class _ChessTrainerPageState extends State<ChessTrainerPage> {
  late Position pos;
  final history = <MoveRecord>[];

  // 모드
  int tab = 0; // 0:튜토, 1:코치, 2:퍼즐, 3:연습
  int lessonIndex = 0;
  int puzzleIndex = 0;
  bool coachHint = true; // 코치 팁 노출 여부
  bool coachPlaysBlack = true; // 코치=흑 (입문자가 백)

  // 학습 흐름 제어
  bool _coachBusy = false;       // 코치가 두는 중
  bool autoReply = true;         // 사용자 수 이후 자동 응수

  Side get userSide => coachPlaysBlack ? Side.white : Side.black;

  /// 모드별 사용자 진영
  Side get _userSideForMode {
    if (tab == 1) return userSide;                    // 코치 대국: 토글에 따름
    if (tab == 2) return puzzles[puzzleIndex].toMove; // 퍼즐: 퍼즐 정의 차례
    if (tab == 0) return Side.white;                  // 튜토리얼: 기본 백
    return pos.stm;                                   // 연습판: 자유
  }

  /// 지금 사용자의 차례인가?
  bool get _isUsersTurnNow => pos.stm == _userSideForMode;

  // 좌표 입력 (자판 이동)
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadStart();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _loadStart() {
    pos = Position.start();
    history.clear();
    _clearInputs();
    setState(() {});
  }

  void _loadLesson(int idx) {
    lessonIndex = idx.clamp(0, lessons.length - 1);
    pos = Position.fromFEN(lessons[lessonIndex].fen);
    history.clear();
    _clearInputs();
    setState(() {});
  }

  void _loadPuzzle(int idx) {
    puzzleIndex = idx.clamp(0, puzzles.length - 1);
    final p = puzzles[puzzleIndex];
    pos = Position.fromFEN(p.fen);
    pos.stm = p.toMove;
    history.clear();
    _clearInputs();
    setState(() {});
  }

  void _switchTab(int t) {
    tab = t;
    if (tab == 0) {
      _loadLesson(lessonIndex);
    } else if (tab == 1) {
      _loadStart();
    } else if (tab == 2) {
      _loadPuzzle(puzzleIndex);
    } else {
      _loadStart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true, // 키보드에 맞춰 레이아웃 재배치
      appBar: AppBar(
        title: const Text('체스 트레이너 • 입문'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: '되돌리기',
              onPressed: history.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: '초기화',
              onPressed: () {
                if (tab == 0) {
                  _loadLesson(lessonIndex);
                } else if (tab == 2) {
                  _loadPuzzle(puzzleIndex);
                } else {
                  _loadStart();
                }
              },
              icon: const Icon(Icons.restart_alt)),
        ],
      ),
      body: Column(
        children: [
          _modeBar(cs),
          if (tab == 0) _lessonBanner(),
          if (tab == 2) _puzzleBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                // 🔧 보드 크기 산출: 상태바/간격 확보(120 + 8)
                const reservedForStatus = 120.0; // 필요시 100~140 사이로 조정
                final side = min(
                  cons.maxWidth,
                  max(0.0, cons.maxHeight - reservedForStatus - 8.0),
                );

                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: side,
                        height: side,
                        child: _boardWidget(side),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: side),
                        child: _statusBar(cs),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // ▼ 입력 바: 키패드가 뜨면 위로 올라오도록 한다
          AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: _entryBar(cs),
          ),
        ],
      ),
      // 자동 응수 모델로 변경 → 플로팅 버튼 사용하지 않음
      floatingActionButton: null,
    );
  }

  Widget _modeBar(ColorScheme cs) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _segItem('튜토리얼', 0),
          _segItem('코치와 대국', 1),
          _segItem('퍼즐', 2),
          _segItem('연습판', 3),
          const Spacer(),
          if (tab == 1)
            Row(children: [
              Switch(
                  value: coachHint,
                  onChanged: (v) => setState(() => coachHint = v)),
              const Text('힌트'),
              const SizedBox(width: 8),
              Switch(
                  value: coachPlaysBlack,
                  onChanged: (v) => setState(() => coachPlaysBlack = v)),
              const Text('코치=흑'),
              const SizedBox(width: 8),
            ]),
        ],
      ),
    );
  }

  Widget _segItem(String label, int value) {
    final active = tab == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: active ? Colors.black : Colors.black87)),
        selected: active,
        onSelected: (_) => _switchTab(value),
      ),
    );
  }

  Widget _lessonBanner() {
    final L = lessons[lessonIndex];
    return Container(
      width: double.infinity,
      color: Colors.amber[50],
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('레슨 ${lessonIndex + 1}/${lessons.length} · ${L.title}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(L.description),
                    const SizedBox(height: 2),
                    Text('목표: ${L.goal}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ])),
          IconButton(
              onPressed: () =>
                  _loadLesson((lessonIndex - 1).clamp(0, lessons.length - 1)),
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              onPressed: () =>
                  _loadLesson((lessonIndex + 1).clamp(0, lessons.length - 1)),
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }

  Widget _puzzleBanner() {
    final P = puzzles[puzzleIndex];
    return Container(
      width: double.infinity,
      color: Colors.blue[50],
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('퍼즐 ${puzzleIndex + 1}/${puzzles.length} · ${P.title}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('차례: ${P.toMove == Side.white ? '백' : '흑'}  ·  힌트: ${P.hint}'),
            ])),
        IconButton(
            onPressed: () =>
                _loadPuzzle((puzzleIndex - 1).clamp(0, puzzles.length - 1)),
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            onPressed: () =>
                _loadPuzzle((puzzleIndex + 1).clamp(0, puzzles.length - 1)),
            icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  Widget _boardWidget(double size) {
    final sqSize = size / 8.0;
    // 탭 이동 비활성(자판 이동만 허용)
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      itemBuilder: (context, i) {
        final r = i ~/ 8, f = i % 8;
        final dark = (r + f).isOdd;
        final sq = BoardPos.rf(r, f);
        final p = pos.board[sq];
        return Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF769656) : const Color(0xFFEEEED2),
            border: Border.all(color: Colors.black12, width: .4),
          ),
          child: Stack(
            children: [
              if (r == 7)
                Positioned(
                    right: 2,
                    bottom: 2,
                    child: Text(
                        String.fromCharCode('a'.codeUnitAt(0) + f),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.black54))),
              if (f == 0)
                Positioned(
                    left: 2,
                    top: 2,
                    child: Text((8 - r).toString(),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.black54))),
              if (p != null)
                Center(
                    child: Text(p.glyph,
                        style: TextStyle(fontSize: sqSize * 0.58, height: 1.0))),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBar(ColorScheme cs) {
    Widget _pillLocal(String s) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(.06),
            borderRadius: BorderRadius.circular(999)),
        child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
    }

    final stm = pos.stm == Side.white ? '백' : '흑';
    final inCheck = Attack.isKingInCheck(pos, pos.stm);
    final statusText = inCheck ? '$stm 체크!' : '$stm 차례';
    final adv = coachHint ? _quickEvalAdvice() : null;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 6)]),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _pillLocal(statusText),
              _pillLocal('캐슬: ${_castlingStr()}'),
              _pillLocal('반수카운트: ${pos.halfmoveClock}'),
              if (adv != null) _pillLocal(adv),
            ],
          ),
          if (tab == 1 && coachHint) const SizedBox(height: 6),
          if (tab == 1 && coachHint)
            Text(_coachText(), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _entryBar(ColorScheme cs) {
    final labelStyle =
    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black54);

    // 연습판(tab=3) 제외 → 사용자 차례&코치대기시에만 입력 가능
    final enabled = (tab == 3) ? true : (_isUsersTurnNow && !_coachBusy);

    InputDecoration deco(String label, String hint) => InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: labelStyle,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          if (!enabled && tab != 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_coachBusy)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  if (_coachBusy) const SizedBox(width: 8),
                  Text(
                    _coachBusy ? '코치가 두는 중...' : '지금은 코치 차례입니다.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // 선택칸 (from)
              Expanded(
                child: TextField(
                  controller: _fromCtrl,
                  focusNode: _fromFocus,
                  readOnly: !enabled,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.none,
                  enableSuggestions: false,
                  autocorrect: false,
                  inputFormatters: [SquareTextFormatter()],
                  decoration: deco('선택', '예: e2'),
                  onChanged: (v) {
                    if (!enabled) return;
                    if (v.length == 2) {
                      FocusScope.of(context).requestFocus(_toFocus);
                    }
                  },
                  onSubmitted: (_) {
                    if (enabled) {
                      FocusScope.of(context).requestFocus(_toFocus);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 목표칸 (to)
              Expanded(
                child: TextField(
                  controller: _toCtrl,
                  focusNode: _toFocus,
                  readOnly: !enabled,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.none,
                  enableSuggestions: false,
                  autocorrect: false,
                  inputFormatters: [SquareTextFormatter()],
                  decoration: deco('목표', '예: e4'),
                  onSubmitted: (_) {
                    if (enabled) _executeTypedMove();
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: enabled ? _executeTypedMove : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[700],
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                child: const Text('실행', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () {
                  _clearInputs();
                  FocusScope.of(context).requestFocus(_fromFocus);
                },
                child: const Text('취소'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '입력 형식: 알파벳(a–h) 1글자 + 숫자(1–8) 1글자, 예) e2 → e4',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  void _clearInputs() {
    _fromCtrl.clear();
    _toCtrl.clear();
  }

  // 좌표 문자열(e2 등)을 인덱스(0..63)로
  int? _parseSquare(String s) {
    if (s.length != 2) return null;
    final fileCh = s[0].toLowerCase();
    final rankCh = s[1];
    if (!RegExp(r'^[a-h]$').hasMatch(fileCh)) return null;
    if (!RegExp(r'^[1-8]$').hasMatch(rankCh)) return null;
    final f = fileCh.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final r = 8 - int.parse(rankCh);
    return BoardPos.rf(r, f);
  }

  void _executeTypedMove() {
    // 연습판 제외 → 사용자 차례가 아니면 차단
    if (tab != 3 && !_isUsersTurnNow) {
      _toast('지금은 코치 차례입니다.');
      return;
    }

    final fromStr = _fromCtrl.text.trim().toLowerCase();
    final toStr = _toCtrl.text.trim().toLowerCase();
    final from = _parseSquare(fromStr);
    final to = _parseSquare(toStr);

    if (from == null || to == null) {
      _toast('올바른 칸을 입력하세요. 예: e2, e4');
      return;
    }

    final legal = MoveGen.legalMoves(pos);
    // 정확히 일치하는 수
    Move? pick = legal.firstWhere(
          (m) => m.from == from && m.to == to && m.promotion == null,
      orElse: () => const Move(from: -1, to: -1),
    );
    if (pick.from == -1) pick = null;

    // 프로모션: 기본 퀸 선택
    if (pick == null) {
      final promos =
      legal.where((m) => m.from == from && m.to == to && m.promotion != null).toList();
      if (promos.isNotEmpty) {
        final q = promos
            .firstWhere((m) => m.promotion == PieceType.queen, orElse: () => promos.first);
        pick = q;
      }
    }

    if (pick == null) {
      _toast('해당 경로는 합법 수가 아닙니다.');
      return;
    }

    _makeMove(pick);
    // 입력 초기화 및 포커스 되돌리기
    _clearInputs();
    FocusScope.of(context).requestFocus(_fromFocus);

    // ✅ 자동 응수: 레슨/코치/퍼즐에서만(연습판 제외), 지금 차례가 코치라면
    if (autoReply && tab != 3 && pos.stm != _userSideForMode) {
      _coachAuto();
    }
  }

  void _undo() {
    if (history.isEmpty) return;
    final saved = [...history];
    final startFEN = (tab == 0)
        ? lessons[lessonIndex].fen
        : (tab == 2 ? puzzles[puzzleIndex].fen : _startFEN);
    pos = Position.fromFEN(startFEN);
    if (tab == 2) pos.stm = puzzles[puzzleIndex].toMove;
    history.clear();
    for (int i = 0; i < saved.length - 1; i++) {
      final nn = Engine.applyMove(pos, saved[i].m);
      if (nn == null) break;
      pos = nn;
      history.add(saved[i]);
    }
    setState(() {});
  }

  void _makeMove(Move m) {
    final captured = pos.board[m.to];
    final next = Engine.applyMove(pos, m);
    if (next == null) return;
    setState(() {
      pos = next;
      history.add(MoveRecord(m, captured));
    });

    // 레슨/퍼즐 판정
    if (tab == 0) {
      final L = lessons[lessonIndex];
      if (L.isCleared(pos, history)) {
        _toast('레슨 성공! 다음 레슨으로 넘어가 보세요.');
      } else if (coachHint) {
        _coachAdvice();
      }
    } else if (tab == 2) {
      final P = puzzles[puzzleIndex];
      if (P.isSolved(pos, history)) {
        _toast('퍼즐 성공!');
      }
    }
  }

  Future<void> _coachAuto() async {
    if (_coachBusy) return;
    setState(() => _coachBusy = true);
    await Future.delayed(const Duration(milliseconds: 350));
    final m = Engine.pickMove(pos);
    if (m == null) {
      _toast('게임 종료(체크메이트/스테일메이트 가능)');
      setState(() => _coachBusy = false);
      return;
    }
    final captured = pos.board[m.to];
    final next = Engine.applyMove(pos, m);
    if (next != null) {
      setState(() {
        pos = next;
        history.add(MoveRecord(m, captured));
        _coachBusy = false;
      });
    } else {
      setState(() => _coachBusy = false);
    }
  }

  String _castlingStr() {
    final s = [
      if (pos.wkCastle) 'K',
      if (pos.wqCastle) 'Q',
      if (pos.bkCastle) 'k',
      if (pos.bqCastle) 'q'
    ].join();
    return s.isEmpty ? '-' : s;
  }

  String? _quickEvalAdvice() {
    if (!coachHint) return null;
    final score = Engine.evaluate(Engine._ensureSide(pos, Side.white));
    String who = score > 100
        ? '백 우세'
        : score < -100
        ? '흑 우세'
        : '균형';
    return '평가: $who';
  }

  void _coachAdvice() {
    final stm = pos.stm;
    final me = stm == Side.white ? '백' : '흑';
    String tip =
        '중앙(d4, d5, e4, e5)을 통제하세요. 나이트/비숍을 먼저 전개하고, 같은 말 반복 이동은 피하세요.';
    if (_canCastle(pos, stm)) {
      tip += ' 캐슬링으로 킹을 안전하게 만드는 것도 좋아요.';
    }
    _toast('[코치] $me: $tip');
  }

  bool _canCastle(Position p, Side s) {
    if (s == Side.white) return p.wkCastle || p.wqCastle;
    return p.bkCastle || p.bqCastle;
  }

  String _coachText() {
    final moves = MoveGen.legalMoves(pos);
    if (moves.isEmpty) {
      final inCheck = Attack.isKingInCheck(pos, pos.stm);
      return inCheck ? '체크메이트입니다.' : '스테일메이트입니다.';
    }
    final best = Engine.pickMove(pos);
    if (best == null) return '가능한 수가 거의 없습니다.';
    final from = BoardPos.algebraic(best.from), to = BoardPos.algebraic(best.to);
    return '추천 수: $from → $to (합법 수 ${moves.length}개)';
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
}

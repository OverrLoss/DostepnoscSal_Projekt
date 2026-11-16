import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum Direction { up, down, left, right }

enum GameDifficulty {
  easy('Łatwy', 220),
  medium('Średni', 140),
  hard('Trudny', 80);

  final String label;
  final int speedMs;
  const GameDifficulty(this.label, this.speedMs);
}

class SnakeGamePage extends StatefulWidget {
  const SnakeGamePage({super.key});

  @override
  State<SnakeGamePage> createState() => _SnakeGamePageState();
}

class _SnakeGamePageState extends State<SnakeGamePage> {
  static const int gridColumns = 20;
  static const int gridRows = 20;

  // Game state
  List<Point<int>> snake = [];
  Point<int> food = const Point(0, 0);
  Point<int>? specialFood;
  int specialFoodTicksLeft = 0;

  Direction direction = Direction.right;
  Direction nextDirection = Direction.right;

  bool isPlaying = false;
  bool isPaused = false;
  bool isGameOver = false;
  bool wallCollision = true; // Wall collision mode vs wrap-around mode

  int score = 0;
  int highScore = 0;
  GameDifficulty selectedDifficulty = GameDifficulty.medium;

  Timer? _timer;
  final Random _random = Random();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _resetGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetGame() {
    setState(() {
      snake = [
        const Point(10, 10),
        const Point(9, 10),
        const Point(8, 10),
      ];
      direction = Direction.right;
      nextDirection = Direction.right;
      score = 0;
      isPlaying = false;
      isPaused = false;
      isGameOver = false;
      specialFood = null;
      specialFoodTicksLeft = 0;
      _spawnFood();
    });
  }

  void _startGame() {
    if (isPlaying) return;
    setState(() {
      isPlaying = true;
      isPaused = false;
      isGameOver = false;
    });
    _focusNode.requestFocus();
    _runTimer();
  }

  void _runTimer() {
    _timer?.cancel();
    // Speed slightly increases as score grows (up to a limit)
    int currentSpeed = max(
      40,
      selectedDifficulty.speedMs - (score ~/ 50) * 5,
    );
    _timer = Timer.periodic(Duration(milliseconds: currentSpeed), (_) {
      if (!isPaused && isPlaying) {
        _gameLoop();
      }
    });
  }

  void _pauseGame() {
    setState(() {
      isPaused = true;
    });
  }

  void _resumeGame() {
    setState(() {
      isPaused = false;
    });
    _focusNode.requestFocus();
  }

  void _spawnFood() {
    Point<int> newFood;
    do {
      newFood = Point(
        _random.nextInt(gridColumns),
        _random.nextInt(gridRows),
      );
    } while (snake.contains(newFood));
    food = newFood;
  }

  void _maybeSpawnSpecialFood() {
    // 20% chance to spawn special food if none exists
    if (specialFood == null && _random.nextInt(100) < 20) {
      Point<int> newSpecial;
      do {
        newSpecial = Point(
          _random.nextInt(gridColumns),
          _random.nextInt(gridRows),
        );
      } while (snake.contains(newSpecial) || newSpecial == food);
      specialFood = newSpecial;
      specialFoodTicksLeft = 30; // Spawns for 30 game steps
    }
  }

  void _changeDirection(Direction newDir) {
    // Prevent opposite direction turns
    if (direction == Direction.up && newDir == Direction.down) return;
    if (direction == Direction.down && newDir == Direction.up) return;
    if (direction == Direction.left && newDir == Direction.right) return;
    if (direction == Direction.right && newDir == Direction.left) return;

    nextDirection = newDir;
  }

  void _gameLoop() {
    direction = nextDirection;
    Point<int> head = snake.first;
    Point<int> newHead;

    switch (direction) {
      case Direction.up:
        newHead = Point(head.x, head.y - 1);
        break;
      case Direction.down:
        newHead = Point(head.x, head.y + 1);
        break;
      case Direction.left:
        newHead = Point(head.x - 1, head.y);
        break;
      case Direction.right:
        newHead = Point(head.x + 1, head.y);
        break;
    }

    // Handle Wall Collision or Wrap Around
    if (wallCollision) {
      if (newHead.x < 0 ||
          newHead.x >= gridColumns ||
          newHead.y < 0 ||
          newHead.y >= gridRows) {
        _triggerGameOver();
        return;
      }
    } else {
      int wrappedX = (newHead.x + gridColumns) % gridColumns;
      int wrappedY = (newHead.y + gridRows) % gridRows;
      newHead = Point(wrappedX, wrappedY);
    }

    // Handle Self Collision
    if (snake.contains(newHead)) {
      _triggerGameOver();
      return;
    }

    // Move Snake
    setState(() {
      snake.insert(0, newHead);

      // Check Normal Food
      if (newHead == food) {
        score += 10;
        if (score > highScore) {
          highScore = score;
        }
        _spawnFood();
        _maybeSpawnSpecialFood();
        _runTimer(); // Adjust speed if threshold met
      } else if (specialFood != null && newHead == specialFood) {
        // Special food eaten
        score += 35;
        if (score > highScore) {
          highScore = score;
        }
        specialFood = null;
        specialFoodTicksLeft = 0;
      } else {
        // Remove tail
        snake.removeLast();
      }

      // Manage Special Food Timer
      if (specialFood != null) {
        specialFoodTicksLeft--;
        if (specialFoodTicksLeft <= 0) {
          specialFood = null;
        }
      }
    });
  }

  void _triggerGameOver() {
    _timer?.cancel();
    setState(() {
      isPlaying = false;
      isGameOver = true;
    });
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.keyW) {
        _changeDirection(Direction.up);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.keyS) {
        _changeDirection(Direction.down);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.keyA) {
        _changeDirection(Direction.left);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.keyD) {
        _changeDirection(Direction.right);
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        if (!isPlaying) {
          _startGame();
        } else if (isPaused) {
          _resumeGame();
        } else {
          _pauseGame();
        }
      }
    }
  }

  void _handleSwipe(DragUpdateDetails details) {
    final dx = details.delta.dx;
    final dy = details.delta.dy;

    if (dx.abs() > dy.abs()) {
      if (dx > 0) {
        _changeDirection(Direction.right);
      } else {
        _changeDirection(Direction.left);
      }
    } else {
      if (dy > 0) {
        _changeDirection(Direction.down);
      } else {
        _changeDirection(Direction.up);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1020),
        appBar: AppBar(
          title: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gamepad, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text(
                'SNAKE GAME',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF121A31),
          elevation: 4,
          actions: [
            IconButton(
              icon: Icon(
                wallCollision ? Icons.border_outer : Icons.crop_free,
                color: wallCollision ? Colors.redAccent : Colors.lightBlueAccent,
              ),
              tooltip: wallCollision ? 'Ściany: Włączone' : 'Ściany: Przenikanie',
              onPressed: () {
                setState(() {
                  wallCollision = !wallCollision;
                });
              },
            )
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Header Status Panel (Score & High Score)
              _buildHeaderPanel(),

              // Game Board Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121A31),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: wallCollision
                              ? Colors.redAccent.withValues(alpha: 0.5)
                              : Colors.greenAccent.withValues(alpha: 0.5),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: GestureDetector(
                        onPanUpdate: _handleSwipe,
                        child: Stack(
                          children: [
                            _buildGrid(),
                            if (!isPlaying && !isGameOver) _buildStartOverlay(),
                            if (isPaused) _buildPauseOverlay(),
                            if (isGameOver) _buildGameOverOverlay(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Controls Panel
              _buildControlsPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121A31),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Current Score
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WYNIK',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$score',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // Difficulty Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF232E52),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<GameDifficulty>(
              value: selectedDifficulty,
              dropdownColor: const Color(0xFF232E52),
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.greenAccent),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              onChanged: isPlaying
                  ? null
                  : (val) {
                      if (val != null) {
                        setState(() {
                          selectedDifficulty = val;
                        });
                      }
                    },
              items: GameDifficulty.values.map((diff) {
                return DropdownMenuItem(
                  value: diff,
                  child: Text(diff.label),
                );
              }).toList(),
            ),
          ),

          // High Score
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'REKORD',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$highScore',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: gridColumns * gridRows,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumns,
      ),
      itemBuilder: (context, index) {
        final x = index % gridColumns;
        final y = index ~/ gridColumns;
        final point = Point(x, y);

        final isHead = snake.isNotEmpty && snake.first == point;
        final isBody = snake.contains(point) && !isHead;
        final isFood = food == point;
        final isSpecial = specialFood == point;

        if (isHead) {
          return Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.8),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        } else if (isBody) {
          return Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        } else if (isFood) {
          return Container(
            margin: const EdgeInsets.all(2.0),
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red,
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          );
        } else if (isSpecial) {
          return Container(
            margin: const EdgeInsets.all(1.5),
            decoration: const BoxDecoration(
              color: Colors.amberAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.amber,
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.star, size: 10, color: Colors.black),
            ),
          );
        } else {
          return Container(
            margin: const EdgeInsets.all(0.5),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1020).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }
      },
    );
  }

  Widget _buildStartOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_fill, size: 64, color: Colors.greenAccent),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              child: const Text('ROZPOCZNIJ GRĘ'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Przesuwaj palcem, używaj przycisków lub strzałek',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUZA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _resumeGame,
              icon: const Icon(Icons.play_arrow),
              label: const Text('WZNÓW'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                _resetGame();
                _startGame();
              },
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('RESTART', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_very_dissatisfied, size: 64, color: Colors.redAccent),
            const SizedBox(height: 8),
            const Text(
              'KONIEC GRY!',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Twój wynik: $score',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            if (score == highScore && score > 0)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text(
                  '🏆 NOWY REKORD! 🏆',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                _resetGame();
                _startGame();
              },
              icon: const Icon(Icons.replay),
              label: const Text('ZAGRAJ PONOWNIE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsPanel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // On-Screen D-Pad
          Column(
            children: [
              IconButton.filledTonal(
                onPressed: () => _changeDirection(Direction.up),
                icon: const Icon(Icons.arrow_drop_up, size: 32),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF232E52),
                  foregroundColor: Colors.white,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _changeDirection(Direction.left),
                    icon: const Icon(Icons.arrow_left, size: 32),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF232E52),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 32),
                  IconButton.filledTonal(
                    onPressed: () => _changeDirection(Direction.right),
                    icon: const Icon(Icons.arrow_right, size: 32),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF232E52),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              IconButton.filledTonal(
                onPressed: () => _changeDirection(Direction.down),
                icon: const Icon(Icons.arrow_drop_down, size: 32),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF232E52),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),

          // Action buttons (Pause/Restart)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton.small(
                heroTag: 'pauseBtn',
                onPressed: () {
                  if (!isPlaying) return;
                  if (isPaused) {
                    _resumeGame();
                  } else {
                    _pauseGame();
                  }
                },
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
                child: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: 'resetBtn',
                onPressed: () {
                  _resetGame();
                },
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                child: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

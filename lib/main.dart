import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:collection';

final String r_arrow = '\u2192';
final String l_arrow = '\u2190';

// Memory management constants
const int MAX_GAME_HISTORY = 500;

void main() {
  runApp(LiquidTransferApp());
}

class LiquidTransferApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liquid Transfer Simulator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LiquidTransferHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameState {
  final List<int> amounts;
  final String description;
  final DateTime timestamp;

  GameState({
    required this.amounts,
    required this.description,
    required this.timestamp,
  });

  GameState.copy(GameState other)
      : amounts = List.from(other.amounts),
        description = other.description,
        timestamp = other.timestamp;
}

class LiquidTransferHome extends StatefulWidget {
  @override
  _LiquidTransferHomeState createState() => _LiquidTransferHomeState();
}

class _LiquidTransferHomeState extends State<LiquidTransferHome>
    with TickerProviderStateMixin {
  final TextEditingController _capacitiesController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  
  List<int> jarCapacities = [];
  List<int> currentAmounts = [];
  int targetQuantity = 0;
  bool isSetup = false;
  List<GameState> gameHistory = [];
  int totalStepCount = 0; // Persistent step counter
  bool isSolving = false;
  bool isPouring = false;
  bool _cancelSolving = false;
  
  int? dragSourceIndex;
  late AnimationController _pourAnimationController;
  late Animation<double> _pourAnimation;

  @override
  void initState() {
    super.initState();
    _pourAnimationController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );
    _pourAnimation = CurvedAnimation(
      parent: _pourAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pourAnimationController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _parseInputAndSetup() {
    try {
      // Validate capacities input
      String capacitiesText = _capacitiesController.text.trim();
      if (capacitiesText.isEmpty) {
        _showErrorMessage('Please enter jar capacities');
        return;
      }

      List<String> capacityStrings = capacitiesText
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      
      if (capacityStrings.isEmpty) {
        _showErrorMessage('Please enter at least one jar capacity');
        return;
      }

      if (capacityStrings.length > 10) {
        _showErrorMessage('Maximum 10 jars allowed');
        return;
      }

      // Parse and validate jar capacities
      List<int> tempCapacities = [];
      for (String capacityStr in capacityStrings) {
        int capacity = int.parse(capacityStr);
        if (capacity <= 0) {
          _showErrorMessage('Jar capacities must be positive numbers');
          return;
        }
        if (capacity > 10000) {
          _showErrorMessage('Jar capacities must be 10000 or less');
          return;
        }
        tempCapacities.add(capacity);
      }
      
      // Validate target quantity
      String targetText = _targetController.text.trim();
      if (targetText.isEmpty) {
        _showErrorMessage('Please enter a target quantity');
        return;
      }

      int tempTarget = int.parse(targetText);
      if (tempTarget <= 0) {
        _showErrorMessage('Target quantity must be positive');
        return;
      }

      int maxCapacity = tempCapacities.reduce((a, b) => a > b ? a : b);
      if (tempTarget > maxCapacity) {
        _showErrorMessage('Target cannot be larger than the biggest jar (${maxCapacity}L)');
        return;
      }

      // Check if target is definitely impossible (GCD check)
      if (_isTargetImpossible(tempCapacities, tempTarget)) {
        _showErrorMessage('Target ${tempTarget}L is mathematically impossible with these jar sizes');
        return;
      }

      // All validations passed
      jarCapacities = tempCapacities;
      targetQuantity = tempTarget;
      
      _resetToInitialState();
      
      setState(() {
        isSetup = true;
      });
    } catch (e) {
      if (e is FormatException) {
        _showErrorMessage('Please enter valid whole numbers only');
      } else {
        _showErrorMessage('Invalid input: ${e.toString()}');
      }
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  bool _isTargetImpossible(List<int> capacities, int target) {
    // Check if target is definitely impossible using GCD of all capacities
    // Note: This only catches obviously impossible cases, not all impossible ones
    int gcd = capacities.first;
    for (int capacity in capacities.skip(1)) {
      gcd = _gcd(gcd, capacity);
    }
    return target % gcd != 0;
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      int temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

  void _resetToInitialState() {
    // Initialize: largest jar full, others empty
    currentAmounts = List.filled(jarCapacities.length, 0);
    int maxCapacity = jarCapacities.reduce(max);
    int largestJarIndex = jarCapacities.indexOf(maxCapacity);
    currentAmounts[largestJarIndex] = maxCapacity;
    
    // Clear history and reset step counter
    gameHistory.clear();
    totalStepCount = 0;
    gameHistory.add(GameState(
      amounts: List.from(currentAmounts),
      description: 'Largest jar (${maxCapacity}L) filled',
      timestamp: DateTime.now(),
    ));
  }

  void _addToHistory(String description) {
    totalStepCount++; // Increment persistent counter
    gameHistory.add(GameState(
      amounts: List.from(currentAmounts),
      description: description,
      timestamp: DateTime.now(),
    ));
    
    // Limit history size to prevent memory leaks
    if (gameHistory.length > MAX_GAME_HISTORY) {
      gameHistory.removeRange(0, gameHistory.length - MAX_GAME_HISTORY);
    }
    
    // Auto-scroll to the latest entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _rollbackToState(int index) {
    if (index >= 0 && index < gameHistory.length) {
      setState(() {
        currentAmounts = List.from(gameHistory[index].amounts);
        // Adjust total step count for rollback
        int stepsRemoved = gameHistory.length - 1 - index;
        totalStepCount -= stepsRemoved;
        // Remove all states after the selected one
        gameHistory = gameHistory.sublist(0, index + 1);
      });
    }
  }

  void _clearOldHistory() {
    // Keep only recent history to free memory
    if (gameHistory.length > MAX_GAME_HISTORY ~/ 2) {
      int keepCount = MAX_GAME_HISTORY ~/ 2;
      gameHistory = gameHistory.sublist(gameHistory.length - keepCount);
    }
  }

  void _cancelSolve() {
    setState(() {
      _cancelSolving = true;
      isSolving = false;
    });
  }

  void _pourLiquid(int fromIndex, int toIndex) async {
    // Prevent concurrent pour operations
    if (isPouring || isSolving || fromIndex == toIndex || currentAmounts[fromIndex] == 0) return;
    
    // Set pouring flag to prevent race conditions
    setState(() {
      isPouring = true;
    });
    
    try {
      int availableSpace = jarCapacities[toIndex] - currentAmounts[toIndex];
      int pourAmount = min(currentAmounts[fromIndex], availableSpace);
      
      if (pourAmount <= 0) {
        setState(() {
          isPouring = false;
        });
        return;
      }
      
      // Record the pour action
      String description = '${pourAmount}L from Jar ${fromIndex + 1} to Jar ${toIndex + 1}';
      
      // Animate the pour
      await _pourAnimationController.forward();
      
      setState(() {
        currentAmounts[fromIndex] -= pourAmount;
        currentAmounts[toIndex] += pourAmount;
      });
      
      _addToHistory(description);
      
      await Future.delayed(Duration(milliseconds: 200));
      await _pourAnimationController.reverse();
      
      // Check if target is reached
      if (currentAmounts.contains(targetQuantity)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Target quantity ${targetQuantity}L reached!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      // Always reset the pouring flag
      setState(() {
        isPouring = false;
      });
    }
  }

  Future<List<String>> _solveLiquidTransfer() async {
    if (jarCapacities.isEmpty) return [];
    
    Queue<List<int>> queue = Queue();
    Set<String> visited = Set();
    Map<String, List<String>> paths = {};
    
    List<int> initial = List.from(gameHistory.first.amounts);
    queue.add(initial);
    visited.add(initial.toString());
    paths[initial.toString()] = [];
    
    // Safety limits to prevent hanging
    const int maxIterations = 10000;
    const int maxStates = 50000;
    const int yieldInterval = 50; // Yield to UI every 50 iterations
    int iterations = 0;
    
    while (queue.isNotEmpty && iterations < maxIterations && visited.length < maxStates && !_cancelSolving) {
      iterations++;
      if (iterations < maxIterations / 4) {
        await Future.delayed(Duration(milliseconds: 5));
      }
      List<int> current = queue.removeFirst();
      
      // Check if target is reached in any jar
      if (current.contains(targetQuantity)) {
        return paths[current.toString()]!;
      }
      
      // Yield to UI periodically to prevent blocking
      if (iterations % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
        // Check for cancellation after yielding
        if (_cancelSolving) {
          return [];
        }
      }
      
      // Generate all possible next states
      for (int i = 0; i < current.length; i++) {
        
        // Pour from jar i to jar j
        for (int j = 0; j < current.length; j++) {
          if (i != j && current[i] > 0 && current[j] < jarCapacities[j]) {
            List<int> next = List.from(current);
            int pourAmount = min(current[i], jarCapacities[j] - current[j]);
            next[i] -= pourAmount;
            next[j] += pourAmount;
            String nextKey = next.toString();
            
            if (!visited.contains(nextKey)) {
              visited.add(nextKey);
              queue.add(next);
              paths[nextKey] = List.from(paths[current.toString()]!)
                ..add('${pourAmount}L from jar ${i + 1} to jar ${j + 1}');
            }
          }
        }
      }
    }
    
    return []; // No solution found or limits exceeded
  }

  Future<void> _executeSolution() async {
    setState(() {
      isSolving = true;
      _cancelSolving = false;
    });
    
    List<String> solution = await _solveLiquidTransfer();
    
    if (solution.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text( _cancelSolving ?
            'Solving cancelled' :
            'No solution found - either impossible or too complex'
            ),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        isSolving = false;
      });
      return;
    }
    
    // Reset to initial state
    _resetToInitialState();
    setState(() {});
    await Future.delayed(Duration(milliseconds: 500));
    
    // Execute each step of the solution
    for (String step in solution) {
      await _executeStep(step);
      await Future.delayed(Duration(milliseconds: 800));
    }
    
    setState(() {
      isSolving = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: 1),
        content: Text('Solution completed in ${solution.length} steps!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _executeStep(String step) async {
    if (step.contains('from jar ')) {
      RegExp regex = RegExp(r'(\d+)L from jar (\d+) to jar (\d+)');
      Match? match = regex.firstMatch(step);
      if (match != null) {
        try {
          String? amountStr = match.group(1);
          String? fromJarStr = match.group(2);
          String? toJarStr = match.group(3);
          
          if (amountStr == null || fromJarStr == null || toJarStr == null) {
            return; // Skip malformed step
          }
          
          int amount = int.parse(amountStr);
          int fromJar = int.parse(fromJarStr) - 1;
          int toJar = int.parse(toJarStr) - 1;
          
          // Validate jar indices
          if (fromJar < 0 || fromJar >= jarCapacities.length || 
              toJar < 0 || toJar >= jarCapacities.length) {
            return; // Skip invalid jar indices
          }
          
          // Validate the move is possible
          if (amount <= 0 || amount > currentAmounts[fromJar] || 
              currentAmounts[toJar] + amount > jarCapacities[toJar]) {
            return; // Skip invalid move
          }
          
          setState(() {
            currentAmounts[fromJar] -= amount;
            currentAmounts[toJar] += amount;
          });
          _addToHistory(step);
        } catch (e) {
          // Skip malformed step silently
          return;
        }
      }
    }
  }

  double _getJarHeight(int capacity, {double? maxHeight}) {
    if (jarCapacities.isEmpty) return 0;
    
    // Height directly proportional to capacity
    double baseHeight = 8.0; // 8 pixels per unit of capacity
    double calculatedHeight = capacity * baseHeight;
    
    // If maxHeight is provided, scale all jars proportionally to fit
    if (maxHeight != null) {
      int maxCapacity = jarCapacities.reduce(max);
      double maxCalculatedHeight = maxCapacity * baseHeight;
      if (maxCalculatedHeight > maxHeight) {
        // Scale down proportionally
        double scaleFactor = maxHeight / maxCalculatedHeight;
        calculatedHeight = capacity * baseHeight * scaleFactor;
      }
    }
    
    return calculatedHeight;
  }

  double _getJarWidth(int capacity) {
    if (jarCapacities.isEmpty) return 40;
    int maxCapacity = jarCapacities.reduce(max);
    double maxWidth = 50.0;
    double minWidth = 30.0;
    return minWidth + (maxWidth - minWidth) * (capacity / maxCapacity);
  }

  Widget _buildMiniJar(int jarIndex, int amount, int capacity, {double pixelsPerUnit = 3.0, double? maxHeight}) {
    if (jarCapacities.isEmpty) return Container();
    
    // Height directly proportional to capacity
    double jarHeight = capacity * pixelsPerUnit;
    
    // If maxHeight is provided, scale all jars proportionally to fit
    if (maxHeight != null) {
      int maxCapacity = jarCapacities.reduce(max);
      double maxCalculatedHeight = maxCapacity * pixelsPerUnit;
      if (maxCalculatedHeight > maxHeight) {
        // Scale down proportionally
        double scaleFactor = maxHeight / maxCalculatedHeight;
        jarHeight = capacity * pixelsPerUnit * scaleFactor;
      }
    }
    
    double jarWidth = 12.0; // Fixed width for mini jars
    
    double fillRatio = capacity > 0 ? amount / capacity : 0;
    bool hasTarget = amount == targetQuantity;
    
    return Container(
      width: jarWidth,
      height: jarHeight,
      margin: EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        border: Border.all(
          color: hasTarget ? Colors.green : Colors.blue.shade400,
          width: hasTarget ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(2),
        color: Colors.grey.shade50,
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Liquid
          Container(
            width: double.infinity,
            height: jarHeight * fillRatio,
            decoration: BoxDecoration(
              color: hasTarget 
                  ? Colors.green.shade600
                  : Colors.blue.shade600,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJarsPreview(List<int> amounts, bool isWiderThanTall, {double? maxHistoryHeight}) {
    if (jarCapacities.isEmpty) return Container();
    
    // Calculate max height for mini jars (1/4 of history area height)
    double maxMiniJarHeight = maxHistoryHeight != null ? maxHistoryHeight * 0.25 : double.infinity;
    double extraSpace = 16; // Space for jar numbers and spacing
    
    // Find max capacity to determine container height
    int maxCapacity = jarCapacities.reduce(max);
    double baseMaxHeight = maxCapacity * 3.0; // Same scaling as mini jars
    double actualMaxHeight = maxHistoryHeight != null 
        ? min(baseMaxHeight, maxMiniJarHeight) 
        : baseMaxHeight;
    
    return Container(
      height: actualMaxHeight + extraSpace,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, // Align jar bottoms
        children: List.generate(
          jarCapacities.length,
          (index) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 2),
              _buildMiniJar(index, amounts[index], jarCapacities[index], maxHeight: maxMiniJarHeight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJar(int index, bool isWiderThanTall, double maxJarHeight) {
    if (!isSetup || index >= jarCapacities.length) return Container();
    double hFactor = isWiderThanTall ? 1.0 : 0.8;
    double wFactor = isWiderThanTall ? 1.0 : 0.9;    
    double jarHeight = _getJarHeight(jarCapacities[index], maxHeight: maxJarHeight) * hFactor;
    double jarWidth = _getJarWidth(jarCapacities[index]) * wFactor;
    double fillRatio = jarCapacities[index] > 0 ? currentAmounts[index] / jarCapacities[index] : 0;
    bool hasTarget = currentAmounts[index] == targetQuantity;
    bool isDragSource = dragSourceIndex == index;
    
    Widget jarWidget = DragTarget<int>(
        onAccept: (fromIndex) {
          _pourLiquid(fromIndex, index);
        },
        onWillAccept: (fromIndex) {
          return !isPouring && !isSolving && fromIndex != null && fromIndex != index && currentAmounts[fromIndex!] > 0;
        },
        builder: (context, candidateData, rejectedData) {
          bool isHovered = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: Duration(milliseconds: 200),
            transform: Matrix4.identity()..scale(isHovered ? 1.1 : 1.0),
            child: _buildJarVisual(index, jarHeight, jarWidth, fillRatio, hasTarget, false),
          );
        },
      );

    // Only enable dragging when not pouring or solving
    if (isPouring || isSolving) {
      return jarWidget;
    }

    return Draggable<int>(
      data: index,
      onDragStarted: () {
        setState(() {
          dragSourceIndex = index;
        });
      },
      onDragEnd: (details) {
        setState(() {
          dragSourceIndex = null;
        });
      },
      feedback: Material(
        color: Colors.transparent,
        child: _buildJarVisual(index, jarHeight, jarWidth, fillRatio, hasTarget, true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildJarVisual(index, jarHeight, jarWidth, fillRatio, hasTarget, false),
      ),
      child: jarWidget,
    );
  }

  Widget _buildJarVisual(int index, double jarHeight, double jarWidth, double fillRatio, bool hasTarget, bool isDragging) {
    return Container(
      margin: EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Jar ${index + 1}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          Text(
            '${currentAmounts[index]}/${jarCapacities[index]}L',
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 4),
          Container(
            width: jarWidth,
            height: jarHeight,
            decoration: BoxDecoration(
              border: Border.all(
                color: hasTarget ? Colors.green : Colors.blue.shade400,
                width: hasTarget ? 2 : 1.5,
              ),
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey.shade50,
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Water/liquid
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  width: double.infinity,
                  height: jarHeight * fillRatio,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: hasTarget 
                          ? [Colors.green.shade300, Colors.green.shade600]
                          : [Colors.blue.shade300, Colors.blue.shade600],
                    ),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(4),
                    ),
                  ),
                ),
                // Water surface animation
                if (fillRatio > 0)
                  Positioned(
                    bottom: jarHeight * fillRatio - 1,
                    left: 1,
                    right: 1,
                    child: AnimatedBuilder(
                      animation: _pourAnimation,
                      builder: (context, child) {
                        return Container(
                          height: 1.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5 + _pourAnimation.value * 0.5),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameLog(bool isWiderThanTall) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Game Log (${totalStepCount} steps)',
                    style: isWiderThanTall ?
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )
                    :
                      Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      )
                    ,
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _logScrollController,
                    thumbVisibility: true,
                    thickness: 12, // default is 8
                    child: ListView.builder(
                      controller: _logScrollController,
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: gameHistory.length,
                      itemBuilder: (context, index) {
                        GameState state = gameHistory[index];
                    bool isCurrentState = index == gameHistory.length - 1;
                    
                    return InkWell(
                      onTap: () => _rollbackToState(index),
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 2),
                        padding: EdgeInsets.all(isWiderThanTall ? 8 : 2),
                        decoration: BoxDecoration(
                          color: isCurrentState
                              ? Colors.blue.shade100
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                          border: isCurrentState
                              ? Border.all(color: Colors.blue.shade300)
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          // mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCurrentState
                                    ? Colors.blue
                                    : Colors.grey.shade400,
                              ),
                              child: Center(
                                child: Text(
                                  '${totalStepCount - gameHistory.length + 1 + index}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 11),
                            _buildJarsPreview(state.amounts, isWiderThanTall, maxHistoryHeight: constraints.maxHeight),
                            SizedBox(width: 11),
                            Text(
                              '[${state.amounts.join(', ')}]L',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrentState 
                                          ? FontWeight.bold 
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                ],
                              ),
                            ),
                            if (!isCurrentState)
                              Icon(
                                Icons.replay,
                                size: 20,
                                color: Colors.blue.shade400,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
  Size screenSize = MediaQuery.of(context).size;
  bool isWiderThanTall = screenSize.width > screenSize.height;

    return Scaffold(
      appBar: AppBar(
        title: Text('Liquid Transfer Simulator'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Setup section (always visible)
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSetup) Text(
                      'Setup',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (!isSetup) SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: _capacitiesController,
                            decoration: InputDecoration(
                              labelText: 'Jar Capacities',
                              hintText: 'e.g.: 10,7,3',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        SizedBox(width: isWiderThanTall ? 12 : 3),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _targetController,
                            decoration: InputDecoration(
                              labelText: 'Target',
                              hintText: 'e.g.: 5',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        SizedBox(width: isWiderThanTall ? 12 : 3),
                        ElevatedButton(
                          onPressed: _parseInputAndSetup,
                          child: Text('Start'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          ),
                        ),
                        if (isSetup) SizedBox(width: isWiderThanTall ? 12 : 3),
                        if (isSetup) ElevatedButton(
                          onPressed: isSolving 
                              ? _cancelSolve 
                              : (currentAmounts.contains(targetQuantity) ? null : _executeSolution),
                          
                          child: Text(isSolving ? 'Cancel solve' : 'Solve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSolving 
                                ? Colors.red.shade600 
                                : Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            if (isSetup) ...[
              SizedBox(height: 16),
              // Game area
              Expanded(
                child: isWiderThanTall ?
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Jars section
                      Expanded(
                        flex: 3,
                        child: _buildJarsSection(context,isWiderThanTall),
                      ),
                      SizedBox(width: 16),
                      // Game log section
                      Expanded(
                        flex: 2,
                        child: _buildGameLog(isWiderThanTall),
                      ),
                    ],
                  )
                  :
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        _buildJarsSection(context,isWiderThanTall),
                      SizedBox(width: 16),
                      // Game log section
                      Expanded(
                        // flex: 3,
                        child: _buildGameLog(isWiderThanTall),
                      ),
                    ],
                  )
                  ,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJarsSection(BuildContext context, bool isWiderThanTall) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height for jars (2/3 of available space minus header)
        double headerHeight = 80; // Approximate height for target text and spacing
        double availableHeight = constraints.maxHeight - headerHeight;
        double maxJarHeight = availableHeight * (2.0 / 3.0);
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Target: ${targetQuantity}L',
                  style: isWiderThanTall ?
                  Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.blue.shade700,
                    )
                  :
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.blue.shade700,
                    )
                  ,
                ),
                (currentAmounts.contains(targetQuantity)) ?
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'TARGET REACHED!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    )
                    :
                    Text(
                      'Drag between jars to pour liquid',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                ,
              ],
            ),
            SizedBox(height: isWiderThanTall ? 10 : 3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  jarCapacities.length,
                  (index) => _buildJar(index, isWiderThanTall, maxJarHeight),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
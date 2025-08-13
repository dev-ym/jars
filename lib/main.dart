import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:collection';

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
  bool isSolving = false;
  
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
      List<String> capacityStrings = _capacitiesController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      
      jarCapacities = capacityStrings.map((s) => int.parse(s)).toList();
      targetQuantity = int.parse(_targetController.text.trim());
      
      if (jarCapacities.isEmpty || targetQuantity <= 0) {
        throw Exception('Invalid input');
      }
      
      _resetToInitialState();
      
      setState(() {
        isSetup = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter valid integers')),
      );
    }
  }

  void _resetToInitialState() {
    // Initialize: largest jar full, others empty
    currentAmounts = List.filled(jarCapacities.length, 0);
    int maxCapacity = jarCapacities.reduce(max);
    int largestJarIndex = jarCapacities.indexOf(maxCapacity);
    currentAmounts[largestJarIndex] = maxCapacity;
    
    // Clear history and add initial state
    gameHistory.clear();
    gameHistory.add(GameState(
      amounts: List.from(currentAmounts),
      description: 'Initial state - largest jar (${maxCapacity}L) filled',
      timestamp: DateTime.now(),
    ));
  }

  void _addToHistory(String description) {
    gameHistory.add(GameState(
      amounts: List.from(currentAmounts),
      description: description,
      timestamp: DateTime.now(),
    ));
    
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
        // Remove all states after the selected one
        gameHistory = gameHistory.sublist(0, index + 1);
      });
    }
  }

  void _pourLiquid(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex || currentAmounts[fromIndex] == 0) return;
    
    int availableSpace = jarCapacities[toIndex] - currentAmounts[toIndex];
    int pourAmount = min(currentAmounts[fromIndex], availableSpace);
    
    if (pourAmount <= 0) return;
    
    // Record the pour action
    String description = 'Pour ${pourAmount}L from Jar ${fromIndex + 1} to Jar ${toIndex + 1}';
    
    // Animate the pour
    _pourAnimationController.forward();
    
    setState(() {
      currentAmounts[fromIndex] -= pourAmount;
      currentAmounts[toIndex] += pourAmount;
    });
    
    _addToHistory(description);
    
    await Future.delayed(Duration(milliseconds: 200));
    _pourAnimationController.reverse();
    
    // Check if target is reached
    if (currentAmounts.contains(targetQuantity)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Target quantity ${targetQuantity}L reached!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  List<String> _solveLiquidTransfer() {
    if (jarCapacities.isEmpty) return [];
    
    Queue<List<int>> queue = Queue();
    Set<String> visited = Set();
    Map<String, List<String>> paths = {};
    
    List<int> initial = List.from(gameHistory.first.amounts);
    queue.add(initial);
    visited.add(initial.toString());
    paths[initial.toString()] = [];
    
    while (queue.isNotEmpty) {
      List<int> current = queue.removeFirst();
      
      // Check if target is reached in any jar
      if (current.contains(targetQuantity)) {
        return paths[current.toString()]!;
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
                ..add('Pour ${pourAmount}L from jar ${i + 1} to jar ${j + 1}');
            }
          }
        }
      }
    }
    
    return []; // No solution found
  }

  Future<void> _executeSolution() async {
    setState(() {
      isSolving = true;
    });
    
    List<String> solution = _solveLiquidTransfer();
    
    if (solution.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No solution found for the given target'),
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
        content: Text('Solution completed in ${solution.length} steps!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _executeStep(String step) async {
    if (step.contains('Pour')) {
      RegExp regex = RegExp(r'Pour (\d+)L from jar (\d+) to jar (\d+)');
      Match? match = regex.firstMatch(step);
      if (match != null) {
        int amount = int.parse(match.group(1)!);
        int fromJar = int.parse(match.group(2)!) - 1;
        int toJar = int.parse(match.group(3)!) - 1;
        
        setState(() {
          currentAmounts[fromJar] -= amount;
          currentAmounts[toJar] += amount;
        });
        _addToHistory(step);
      }
    }
  }

  double _getJarHeight(int capacity) {
    // Height directly proportional to capacity
    double baseHeight = 8.0; // 8 pixels per unit of capacity
    return capacity * baseHeight;
  }

  double _getJarWidth(int capacity) {
    if (jarCapacities.isEmpty) return 40;
    int maxCapacity = jarCapacities.reduce(max);
    double maxWidth = 50.0;
    double minWidth = 30.0;
    return minWidth + (maxWidth - minWidth) * (capacity / maxCapacity);
  }

  Widget _buildMiniJar(int jarIndex, int amount, int capacity, {double pixelsPerUnit = 3.0}) {
    if (jarCapacities.isEmpty) return Container();
    
    // Height directly proportional to capacity
    double jarHeight = capacity * pixelsPerUnit;
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

  Widget _buildJarsPreview(List<int> amounts) {
    if (jarCapacities.isEmpty) return Container();
    
    // Find max capacity to determine container height
    int maxCapacity = jarCapacities.reduce(max);
    double maxHeight = maxCapacity * 3.0; // Same scaling as mini jars
    
    return Container(
      height: maxHeight + 16, // Extra space for jar numbers
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
              _buildMiniJar(index, amounts[index], jarCapacities[index]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJar(int index) {
    if (!isSetup || index >= jarCapacities.length) return Container();
    
    double jarHeight = _getJarHeight(jarCapacities[index]);
    double jarWidth = _getJarWidth(jarCapacities[index]);
    double fillRatio = jarCapacities[index] > 0 ? currentAmounts[index] / jarCapacities[index] : 0;
    bool hasTarget = currentAmounts[index] == targetQuantity;
    bool isDragSource = dragSourceIndex == index;
    
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
      child: DragTarget<int>(
        onAccept: (fromIndex) {
          _pourLiquid(fromIndex, index);
        },
        onWillAccept: (fromIndex) {
          return fromIndex != null && fromIndex != index && currentAmounts[fromIndex!] > 0;
        },
        builder: (context, candidateData, rejectedData) {
          bool isHovered = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: Duration(milliseconds: 200),
            transform: Matrix4.identity()..scale(isHovered ? 1.1 : 1.0),
            child: _buildJarVisual(index, jarHeight, jarWidth, fillRatio, hasTarget, false),
          );
        },
      ),
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

  Widget _buildGameLog() {
    return Container(
      height: 300,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Game Log (${gameHistory.length} steps)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _logScrollController,
                thumbVisibility: true,
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
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCurrentState
                              ? Colors.blue.shade100
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: isCurrentState
                              ? Border.all(color: Colors.blue.shade300)
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  '${index}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
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
                                  Row(
                                    children: [
                                      _buildJarsPreview(state.amounts),
                                      SizedBox(width: 8),
                                      Text(
                                        '[${state.amounts.join(', ')}]L',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!isCurrentState)
                              Icon(
                                Icons.replay,
                                size: 16,
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
  }

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      'Setup',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _capacitiesController,
                            decoration: InputDecoration(
                              labelText: 'Jar Capacities',
                              hintText: 'e.g., 3, 5, 8',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _targetController,
                            decoration: InputDecoration(
                              labelText: 'Target',
                              hintText: 'e.g., 4',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _parseInputAndSetup,
                          child: Text('Start'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        if (isSetup) ...[
                          SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isSolving ? null : () {
                              setState(() {
                                _resetToInitialState();
                              });
                            },
                            child: Text('Reset'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade600,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: (isSolving || currentAmounts.contains(targetQuantity)) ? null : _executeSolution,
                            child: Text(isSolving ? 'Solving...' : 'Solve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Jars section
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Target: ${targetQuantity}L',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              if (currentAmounts.contains(targetQuantity))
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
                                ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Drag between jars to pour liquid',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          SizedBox(height: 16),
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(
                                    jarCapacities.length,
                                    (index) => _buildJar(index),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    // Game log section
                    Expanded(
                      flex: 1,
                      child: _buildGameLog(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
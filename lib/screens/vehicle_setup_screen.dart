import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/vehicle_profile.dart';
import '../models/vehicle_preset.dart';
import 'mapscreen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen principal
// ─────────────────────────────────────────────────────────────────────────────
class VehicleSetupScreen extends StatefulWidget {
  const VehicleSetupScreen({super.key});

  @override
  State<VehicleSetupScreen> createState() => _VehicleSetupScreenState();
}

class _VehicleSetupScreenState extends State<VehicleSetupScreen>
    with TickerProviderStateMixin {
  // ── Stepper ──────────────────────────────────────────────────────────────
  int _currentStep = 0;
  final int _totalSteps = 3;

  // ── Étape 1 : carburant ───────────────────────────────────────────────────
  FuelType? _selectedFuelType;

  // ── Étape 2 : catégorie + masse + puissance ───────────────────────────────
  int? _selectedPresetIndex;
  final TextEditingController _massController = TextEditingController();
  final TextEditingController _powerController = TextEditingController();
  final _step2FormKey = GlobalKey<FormState>();

  // ── Étape 3 : consommation constructeur + Cx avancé ───────────────────────
  final TextEditingController _consumptionController = TextEditingController();
  final TextEditingController _cxController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  bool _showAdvanced = false;
  final _step3FormKey = GlobalKey<FormState>();

  bool _isSaving = false;

  // Animations
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _massController.dispose();
    _powerController.dispose();
    _consumptionController.dispose();
    _cxController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  // ── Navigation entre étapes ───────────────────────────────────────────────

  void _applyPreset(int index) {
    final preset = vehiclePresets[index];
    setState(() {
      _selectedPresetIndex = index;
      _massController.text = preset.defaultMassKg.toInt().toString();
      _powerController.text = preset.defaultPowerKw.toInt().toString();
      _cxController.text = preset.cx.toStringAsFixed(2);
      _areaController.text = preset.frontalAreaM2.toStringAsFixed(1);
    });
  }

  bool _validateStep1() {
    if (_selectedFuelType == null) {
      _showError('Veuillez sélectionner un type de carburant.');
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    if (_selectedPresetIndex == null) {
      _showError('Veuillez sélectionner une catégorie de véhicule.');
      return false;
    }
    return _step2FormKey.currentState?.validate() ?? false;
  }

  void _nextStep() {
    bool valid = false;
    if (_currentStep == 0) valid = _validateStep1();
    if (_currentStep == 1) valid = _validateStep2();
    if (_currentStep == 2) valid = true; // validation dans _save()

    if (!valid) return;

    if (_currentStep < _totalSteps - 1) {
      _fadeCtrl.reset();
      setState(() => _currentStep++);
      _fadeCtrl.forward();
    } else {
      _save();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _fadeCtrl.reset();
      setState(() => _currentStep--);
      _fadeCtrl.forward();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_step3FormKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final preset = vehiclePresets[_selectedPresetIndex!];
    final double massKg =
        double.tryParse(_massController.text.replaceAll(',', '.')) ??
        preset.defaultMassKg;
    final double powerKw =
        double.tryParse(_powerController.text.replaceAll(',', '.')) ??
        preset.defaultPowerKw;
    final double consumption = double.parse(
      _consumptionController.text.replaceAll(',', '.'),
    );
    final double cx =
        double.tryParse(_cxController.text.replaceAll(',', '.')) ?? preset.cx;
    final double area =
        double.tryParse(_areaController.text.replaceAll(',', '.')) ??
        preset.frontalAreaM2;

    final profile = VehicleProfile(
      fuelType: _selectedFuelType!,
      consumptionL100: consumption,
      massKg: massKg,
      powerKw: powerKw,
      cx: cx,
      frontalAreaM2: area,
    );
    await profile.save();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MapScreen(vehicleProfile: profile)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _buildHeader(topPad),

          // ── Stepper indicator ─────────────────────────────────────────────
          _buildStepIndicator(),

          // ── Contenu de l'étape ────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: _buildStepContent(),
              ),
            ),
          ),

          // ── Boutons de navigation ─────────────────────────────────────────
          _buildNavigationBar(bottomPad),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(double topPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, topPad + 28, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.18),
            ),
            child: const Icon(Icons.eco_rounded, size: 30, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EcoDriving',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                _stepTitle(),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _stepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Étape 1 · Type de carburant';
      case 1:
        return 'Étape 2 · Caractéristiques du véhicule';
      case 2:
        return 'Étape 3 · Consommation & aérodynamisme';
      default:
        return '';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stepper indicator
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Container(
      color: const Color(0xFF2E7D32),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: List.generate(_totalSteps * 2 - 1, (i) {
          if (i.isOdd) {
            // Ligne de connexion
            final stepIndex = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                color: stepIndex < _currentStep
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isDone = stepIndex < _currentStep;
          final isActive = stepIndex == _currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone || isActive
                  ? Colors.white
                  : Colors.white.withOpacity(0.3),
            ),
            child: Center(
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Color(0xFF2E7D32),
                    )
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive
                            ? const Color(0xFF2E7D32)
                            : Colors.white.withOpacity(0.6),
                      ),
                    ),
            ),
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Contenu des étapes
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Étape 1 : Type de carburant ───────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _sectionTitle('Quel carburant utilise votre véhicule ?'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _FuelTypeCard(
                label: 'Diesel',
                subtitle: 'Gazole · GO',
                icon: Icons.local_gas_station,
                color: const Color(0xFF1565C0),
                selected: _selectedFuelType == FuelType.diesel,
                onTap: () =>
                    setState(() => _selectedFuelType = FuelType.diesel),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _FuelTypeCard(
                label: 'Essence',
                subtitle: 'Sans plomb · SP95/98',
                icon: Icons.local_gas_station_outlined,
                color: const Color(0xFFE65100),
                selected: _selectedFuelType == FuelType.essence,
                onTap: () =>
                    setState(() => _selectedFuelType = FuelType.essence),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _infoBox(
          icon: Icons.info_outline_rounded,
          text:
              'Le type de carburant influence le rendement thermique du moteur '
              '(diesel ≈ 42 %, essence ≈ 35 %) et le pouvoir calorifique utilisés '
              'pour estimer votre consommation en temps réel.',
        ),
      ],
    );
  }

  // ── Étape 2 : Catégorie + masse + puissance ───────────────────────────────

  Widget _buildStep2() {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _sectionTitle('Catégorie de véhicule'),
          const SizedBox(height: 4),
          Text(
            'Sélectionnez votre type de véhicule pour pré-remplir les valeurs aérodynamiques.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          // Grille 2×2 de catégories
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.1,
            ),
            itemCount: vehiclePresets.length,
            itemBuilder: (context, i) {
              final preset = vehiclePresets[i];
              final isSelected = _selectedPresetIndex == i;
              return GestureDetector(
                onTap: () => _applyPreset(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF2E7D32).withOpacity(0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.grey.shade200,
                      width: isSelected ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? const Color(0xFF2E7D32).withOpacity(0.12)
                            : Colors.black.withOpacity(0.04),
                        blurRadius: isSelected ? 10 : 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        preset.icon,
                        size: 22,
                        color: isSelected
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        preset.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF2E7D32)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _sectionTitle('Masse & Puissance'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildNumberField(
                  controller: _massController,
                  label: 'Masse à vide',
                  suffix: 'kg',
                  hint: 'ex : 1350',
                  helperText: 'Indiqué sur la carte grise (champ G)',
                  min: 500,
                  max: 5000,
                  validator: (v) {
                    final val = double.tryParse(v?.replaceAll(',', '.') ?? '');
                    if (val == null || val < 500 || val > 5000) {
                      return 'Entre 500 et 5000 kg';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildNumberField(
                  controller: _powerController,
                  label: 'Puissance',
                  suffix: 'kW',
                  hint: 'ex : 85',
                  helperText: 'Puissance réelle moteur (carte grise champ P2)',
                  min: 20,
                  max: 600,
                  validator: (v) {
                    final val = double.tryParse(v?.replaceAll(',', '.') ?? '');
                    if (val == null || val < 20 || val > 600) {
                      return 'Entre 20 et 600 kW';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoBox(
            icon: Icons.article_outlined,
            text:
                'La masse et la puissance sont indiquées sur votre carte grise : '
                'champ G (masse à vide) et champ P2 (puissance en kW). '
                '1 ch DIN = 0,736 kW si vous n\'avez que les chevaux.',
          ),
        ],
      ),
    );
  }

  // ── Étape 3 : Consommation + Cx avancé ────────────────────────────────────

  Widget _buildStep3() {
    return Form(
      key: _step3FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _sectionTitle('Consommation constructeur'),
          const SizedBox(height: 4),
          Text(
            'Sert de référence pour calibrer les estimations sur trajet complet.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          _buildNumberField(
            controller: _consumptionController,
            label: 'Consommation mixte',
            suffix: 'L/100 km',
            hint: 'ex : 6.5',
            helperText: 'Valeur WLTP ou réelle indiquée dans le manuel',
            min: 1,
            max: 30,
            validator: (v) {
              final val = double.tryParse(v?.replaceAll(',', '.') ?? '');
              if (val == null || val <= 0 || val > 30) {
                return 'Valeur invalide (1 – 30 L/100 km)';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Section avancée (repliable)
          GestureDetector(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Paramètres aérodynamiques avancés',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    _showAdvanced ? 'Masquer' : 'Modifier',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: const Color(0xFF2E7D32),
                  ),
                ],
              ),
            ),
          ),

          if (_showAdvanced) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pré-remplis depuis votre catégorie. Modifiez uniquement si vous connaissez les valeurs exactes.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(
                          controller: _cxController,
                          label: 'Cx',
                          suffix: '',
                          hint: 'ex : 0.28',
                          helperText: 'Coeff. de traînée aérodynamique',
                          min: 0.1,
                          max: 0.7,
                          validator: (v) {
                            final val = double.tryParse(
                              v?.replaceAll(',', '.') ?? '',
                            );
                            if (val == null || val < 0.1 || val > 0.7) {
                              return 'Entre 0.10 et 0.70';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildNumberField(
                          controller: _areaController,
                          label: 'Surface frontale',
                          suffix: 'm²',
                          hint: 'ex : 2.2',
                          helperText: 'Section transversale du véhicule',
                          min: 1.5,
                          max: 4.5,
                          validator: (v) {
                            final val = double.tryParse(
                              v?.replaceAll(',', '.') ?? '',
                            );
                            if (val == null || val < 1.5 || val > 4.5) {
                              return 'Entre 1.5 et 4.5 m²';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Récapitulatif
          _buildSummaryCard(),
        ],
      ),
    );
  }

  // ── Carte récapitulative ──────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    if (_selectedPresetIndex == null || _selectedFuelType == null) {
      return const SizedBox.shrink();
    }
    final preset = vehiclePresets[_selectedPresetIndex!];
    final massKg =
        double.tryParse(_massController.text) ?? preset.defaultMassKg;
    final powerKw =
        double.tryParse(_powerController.text) ?? preset.defaultPowerKw;
    final powerCh = (powerKw / 0.736).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1B5E20).withOpacity(0.06),
            const Color(0xFF2E7D32).withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF2E7D32),
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Récapitulatif du profil',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _summaryChip(
                Icons.local_gas_station_rounded,
                _selectedFuelType == FuelType.diesel ? 'Diesel' : 'Essence',
              ),
              _summaryChip(preset.icon, preset.label),
              _summaryChip(Icons.scale_outlined, '${massKg.toInt()} kg'),
              _summaryChip(
                Icons.bolt_rounded,
                '$powerCh ch (${powerKw.toInt()} kW)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1B5E20),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Barre de navigation bas
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNavigationBar(double bottomPad) {
    final isLastStep = _currentStep == _totalSteps - 1;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Bouton Précédent
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: _prevStep,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Retour'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          else
            const SizedBox.shrink(),

          const Spacer(),

          // Bouton Suivant / Terminer
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _nextStep,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    isLastStep
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
            label: Text(isLastStep ? 'Commencer' : 'Suivant'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers UI
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _infoBox({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade800,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required String hint,
    required String helperText,
    required double min,
    required double max,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix.isNotEmpty ? suffix : null,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: 2,
        helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade600, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      validator: validator,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget carte carburant
// ─────────────────────────────────────────────────────────────────────────────

class _FuelTypeCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FuelTypeCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 2.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? color.withOpacity(0.18)
                  : Colors.black.withOpacity(0.04),
              blurRadius: selected ? 14 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? color : Colors.grey.shade400,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: selected ? color : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: selected ? color.withOpacity(0.7) : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

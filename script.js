/**
 * LOGIFAST · script.js
 * Lógica principal de la calculadora de envíos
 *
 * Arquitectura:
 *   - Estado centralizado (AppState)
 *   - Módulo de validación (Validator)
 *   - Módulo de UI/DOM (UI)
 *   - Módulo de cálculo (Calculator)
 *   - Módulo de preview 3D (Preview3D)
 *   - Bootstrap (init)
 */

'use strict';

/* ═══════════════════════════════════════
   ESTADO CENTRALIZADO
═══════════════════════════════════════ */
const AppState = {
  alto:    null,
  ancho:   null,
  largo:   null,
  destino: null,   // distancia en km
  destName: '',
  resultado: null,
};

/* ═══════════════════════════════════════
   MAPEO DE DESTINOS
═══════════════════════════════════════ */
const DESTINOS = {
  300:  { nombre: 'Rosario',          provincia: 'Santa Fe',  emoji: '🏙️' },
  700:  { nombre: 'Córdoba Capital',  provincia: 'Córdoba',   emoji: '🏛️' },
  1050: { nombre: 'Mendoza',          provincia: 'Mendoza',   emoji: '🍇' },
  1200: { nombre: 'Tucumán',          provincia: 'Tucumán',   emoji: '🎶' },
  1450: { nombre: 'Salta',            provincia: 'Salta',     emoji: '🌄' },
};

const MAX_DIST = 1450; // Para el % de la barra

/* ═══════════════════════════════════════
   MÓDULO DE VALIDACIÓN
═══════════════════════════════════════ */
const Validator = {
  /**
   * Valida un campo numérico.
   * @param {string} fieldId - ID del contenedor de campo
   * @param {number|null} value
   * @param {string} label - Nombre legible del campo
   * @returns {boolean}
   */
  validateNumericField(fieldId, value, label) {
    const fieldEl = document.getElementById(`field-${fieldId}`);
    const msgEl   = fieldEl.querySelector('.field-msg');

    if (value === null || value === '' || isNaN(value)) {
      this._setFieldState(fieldEl, msgEl, 'invalid', `${label} es obligatorio`);
      return false;
    }
    if (value <= 0) {
      this._setFieldState(fieldEl, msgEl, 'invalid', `${label} debe ser mayor a 0`);
      return false;
    }
    if (value > 300) {
      this._setFieldState(fieldEl, msgEl, 'invalid', `${label} no puede superar 300 cm`);
      return false;
    }
    this._setFieldState(fieldEl, msgEl, 'valid', '');
    return true;
  },

  validateDestino() {
    const fieldEl = document.getElementById('field-destino');
    const msgEl   = fieldEl.querySelector('.field-msg');

    if (!AppState.destino) {
      this._setFieldState(fieldEl, msgEl, 'invalid', 'Seleccioná un destino');
      return false;
    }
    this._setFieldState(fieldEl, msgEl, 'valid', '');
    return true;
  },

  _setFieldState(fieldEl, msgEl, state, msg) {
    fieldEl.classList.remove('valid', 'invalid');
    if (state) fieldEl.classList.add(state);
    if (msgEl) msgEl.textContent = msg;
  },

  clearAll() {
    ['alto', 'ancho', 'largo', 'destino'].forEach(id => {
      const el = document.getElementById(`field-${id}`);
      if (el) {
        el.classList.remove('valid', 'invalid');
        const msg = el.querySelector('.field-msg');
        if (msg) msg.textContent = '';
      }
    });
  },

  /**
   * Valida todos los campos y retorna si el formulario es válido.
   */
  validateAll() {
    const a = this.validateNumericField('alto',  AppState.alto,  'Alto');
    const b = this.validateNumericField('ancho', AppState.ancho, 'Ancho');
    const c = this.validateNumericField('largo', AppState.largo, 'Largo');
    const d = this.validateDestino();
    return a && b && c && d;
  },
};

/* ═══════════════════════════════════════
   MÓDULO DE CÁLCULO
═══════════════════════════════════════ */
const Calculator = {
  TARIFA_BASE:    1000,
  FACTOR_VOL:     5000,
  COSTO_KM:       5,
  COSTO_KGVOL:    100,

  calcPesoVol(alto, ancho, largo) {
    return (alto * ancho * largo) / this.FACTOR_VOL;
  },

  calcTotal(pesoVol, distancia) {
    const recargoDist = distancia * this.COSTO_KM;
    const costoVol    = pesoVol   * this.COSTO_KGVOL;
    return {
      base:       this.TARIFA_BASE,
      recargo:    recargoDist,
      costoVol,
      total:      this.TARIFA_BASE + recargoDist + costoVol,
    };
  },
};

/* ═══════════════════════════════════════
   MÓDULO DE PREVIEW 3D
═══════════════════════════════════════ */
const Preview3D = {
  MIN_SIZE: 50,   // px mínimo de cada dimensión visual
  MAX_SIZE: 130,  // px máximo
  REF_DIM:  200,  // dimensión de referencia (cm)

  /**
   * Escala una dimensión real a píxeles CSS para la caja 3D.
   */
  _scale(value) {
    if (!value || value <= 0) return this.MIN_SIZE;
    const scaled = (value / this.REF_DIM) * this.MAX_SIZE;
    return Math.max(this.MIN_SIZE, Math.min(this.MAX_SIZE, scaled));
  },

  update(alto, ancho, largo) {
    const box    = document.getElementById('box3d');
    const shadow = document.getElementById('box3d-shadow');
    if (!box) return;

    const h = this._scale(alto);
    const w = this._scale(ancho);
    const d = this._scale(largo);

    // Actualiza las variables CSS personalizadas de la caja
    box.style.setProperty('--w', `${w}px`);
    box.style.setProperty('--h', `${h}px`);
    box.style.setProperty('--d', `${d}px`);

    // Ajusta la sombra proporcionalmente
    if (shadow) {
      shadow.style.width = `${w * 1.3}px`;
    }
  },

  reset() {
    this.update(null, null, null);
  },
};

/* ═══════════════════════════════════════
   MÓDULO DE TOAST
═══════════════════════════════════════ */
const Toast = {
  container: null,

  init() {
    this.container = document.getElementById('toast-container');
  },

  /**
   * Muestra un toast.
   * @param {string} msg
   * @param {'warning'|'error'|'success'} type
   * @param {number} duration - ms
   */
  show(msg, type = 'warning', duration = 4000) {
    if (!this.container) return;

    const icons = { warning: '⚠️', error: '❌', success: '✅' };

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `
      <span class="toast-icon">${icons[type]}</span>
      <span class="toast-text">${msg}</span>
      <button class="toast-close" aria-label="Cerrar">✕</button>
    `;

    // Botón de cierre
    toast.querySelector('.toast-close').addEventListener('click', () => {
      this._dismiss(toast);
    });

    this.container.appendChild(toast);

    // Auto-dismiss
    const timer = setTimeout(() => this._dismiss(toast), duration);
    toast._timer = timer;
  },

  _dismiss(toast) {
    clearTimeout(toast._timer);
    toast.style.animation = 'toastOut 0.3s ease forwards';
    toast.addEventListener('animationend', () => toast.remove(), { once: true });
  },
};

/* ═══════════════════════════════════════
   MÓDULO DE UI
═══════════════════════════════════════ */
const UI = {
  /**
   * Formatea un número como moneda argentina.
   */
  formatARS(value) {
    return new Intl.NumberFormat('es-AR', {
      style: 'currency',
      currency: 'ARS',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(value);
  },

  /**
   * Genera un ID de cotización aleatorio.
   */
  genCotizacionId() {
    const chars  = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const nums   = '23456789';
    const prefix = Array.from({ length: 3 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
    const suffix = Array.from({ length: 4 }, () => nums[Math.floor(Math.random() * nums.length)]).join('');
    return `LGF-${prefix}${suffix}`;
  },

  /**
   * Actualiza los labels de dimensiones en tiempo real.
   */
  updateDimLabels(alto, ancho, largo) {
    const fmt = v => (v && v > 0) ? `${v} cm` : '— cm';
    document.getElementById('dim-alto').textContent  = fmt(alto);
    document.getElementById('dim-ancho').textContent = fmt(ancho);
    document.getElementById('dim-largo').textContent = fmt(largo);
  },

  /**
   * Actualiza la tarjeta de destino.
   */
  updateDestinoCard(distancia) {
    const destName = document.getElementById('dest-name');
    const distKm   = document.getElementById('dist-km');
    const distTo   = document.getElementById('dist-to');
    const barFill  = document.getElementById('dist-bar-fill');
    const dotDest  = document.getElementById('dist-dot-dest');

    if (!distancia) {
      destName.textContent = 'Sin seleccionar';
      distKm.textContent   = '0 km';
      distTo.textContent   = '—';
      if (barFill)  barFill.style.width   = '0%';
      if (dotDest)  dotDest.style.left    = '0%';
      return;
    }

    const info = DESTINOS[distancia];
    if (info) {
      destName.textContent = `${info.emoji} ${info.nombre}`;
      distTo.textContent   = `📍 ${info.nombre}`;
    }
    distKm.textContent = `${distancia.toLocaleString('es-AR')} km`;

    // Barra proporcional
    const pct = Math.round((distancia / MAX_DIST) * 100);
    if (barFill) barFill.style.width  = `${pct}%`;
    if (dotDest) dotDest.style.left   = `${pct}%`;
  },

  /**
   * Actualiza el panel de estimación instantánea.
   */
  updateLiveEstimate() {
    const { alto, ancho, largo, destino } = AppState;
    const pesoEl = document.getElementById('live-peso');
    const volEl  = document.getElementById('live-vol');
    const estEl  = document.getElementById('live-est');

    const hasAll = alto > 0 && ancho > 0 && largo > 0;

    if (!hasAll) {
      pesoEl.textContent = '—';
      volEl.textContent  = '—';
      estEl.textContent  = '—';
      return;
    }

    const vol     = (alto * ancho * largo) / 1000; // cm³ → dm³ (litros)
    const pesoVol = Calculator.calcPesoVol(alto, ancho, largo);

    pesoEl.textContent = `${pesoVol.toFixed(2)} kg`;
    volEl.textContent  = `${vol.toFixed(1)} L`;

    if (destino) {
      const res = Calculator.calcTotal(pesoVol, destino);
      estEl.textContent = this.formatARS(res.total);
    } else {
      estEl.textContent = '—';
    }
  },

  /**
   * Muestra el panel de resultado.
   */
  showResultado(pesoVol, distancia, calculo) {
    const resultadoEl = document.getElementById('resultado');
    resultadoEl.classList.remove('hidden');

    document.getElementById('cotizacion-id').textContent = `# ${this.genCotizacionId()}`;
    document.getElementById('res-peso').textContent      = `${pesoVol.toFixed(2)} kg`;
    document.getElementById('res-dist').textContent      = `${distancia.toLocaleString('es-AR')} km`;
    document.getElementById('res-base').textContent      = this.formatARS(calculo.base);
    document.getElementById('res-recargo').textContent   = this.formatARS(calculo.recargo);
    document.getElementById('res-total').textContent     = this.formatARS(calculo.total);

    // Scroll suave al resultado
    setTimeout(() => {
      resultadoEl.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }, 100);
  },

  hideResultado() {
    document.getElementById('resultado').classList.add('hidden');
  },
};

/* ═══════════════════════════════════════
   HANDLERS DE EVENTOS
═══════════════════════════════════════ */

/**
 * Callback compartido para los inputs numéricos.
 * Actualiza el estado, labels, caja 3D y estimación en vivo.
 */
function onDimensionChange(field, value) {
  const num = parseFloat(value);
  AppState[field] = isNaN(num) ? null : num;

  UI.updateDimLabels(AppState.alto, AppState.ancho, AppState.largo);
  Preview3D.update(AppState.alto, AppState.ancho, AppState.largo);
  UI.updateLiveEstimate();
}

/**
 * Handler para el select de destino.
 */
function onDestinoChange(value) {
  AppState.destino = value ? parseInt(value, 10) : null;
  UI.updateDestinoCard(AppState.destino);
  UI.updateLiveEstimate();
}

/**
 * Handler del botón principal: valida, calcula, muestra resultado.
 */
function onCalcular() {
  const btn = document.getElementById('btn-calcular');

  // Animación de "cargando"
  btn.disabled = true;
  btn.querySelector('.btn-text').textContent = 'Calculando…';

  setTimeout(() => {
    btn.disabled = false;
    btn.querySelector('.btn-text').textContent = 'Calcular Envío';

    const isValid = Validator.validateAll();
    if (!isValid) {
      Toast.show('Completá todos los campos antes de calcular', 'warning');
      return;
    }

    const { alto, ancho, largo, destino } = AppState;
    const pesoVol = Calculator.calcPesoVol(alto, ancho, largo);
    const calculo = Calculator.calcTotal(pesoVol, destino);

    AppState.resultado = { pesoVol, distancia: destino, calculo };

    UI.showResultado(pesoVol, destino, calculo);
    Toast.show('¡Cotización lista! Revisá el desglose.', 'success', 3000);
  }, 500); // Simula latencia de cálculo para dar feedback visual
}

/**
 * Handler del botón "Nueva consulta".
 */
function onNuevaConsulta() {
  // Reset estado
  AppState.alto = AppState.ancho = AppState.largo = AppState.destino = null;
  AppState.resultado = null;

  // Reset UI
  ['alto', 'ancho', 'largo'].forEach(id => {
    document.getElementById(id).value = '';
  });
  document.getElementById('destino').value = '';

  Validator.clearAll();
  UI.updateDimLabels(null, null, null);
  UI.updateDestinoCard(null);
  UI.updateLiveEstimate();
  Preview3D.reset();
  UI.hideResultado();

  // Scroll al inicio
  document.querySelector('.col-form').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/* ═══════════════════════════════════════
   INICIALIZACIÓN
═══════════════════════════════════════ */
function init() {
  Toast.init();

  // ── Inputs numéricos ──
  const dimensiones = [
    { id: 'alto',  label: 'Alto'  },
    { id: 'ancho', label: 'Ancho' },
    { id: 'largo', label: 'Largo' },
  ];

  dimensiones.forEach(({ id }) => {
    const input = document.getElementById(id);
    if (!input) return;

    // Actualización en tiempo real mientras escribe
    input.addEventListener('input', () => {
      onDimensionChange(id, input.value);
    });

    // Validación al salir del campo
    input.addEventListener('blur', () => {
      const num = parseFloat(input.value);
      if (input.value.trim() !== '') {
        Validator.validateNumericField(id, num, id.charAt(0).toUpperCase() + id.slice(1));
      }
    });

    // Elimina estado de error al empezar a escribir
    input.addEventListener('focus', () => {
      const fieldEl = document.getElementById(`field-${id}`);
      fieldEl.classList.remove('invalid');
      fieldEl.querySelector('.field-msg').textContent = '';
    });
  });

  // ── Select de destino ──
  const selectDestino = document.getElementById('destino');
  if (selectDestino) {
    selectDestino.addEventListener('change', () => {
      onDestinoChange(selectDestino.value);
    });
  }

  // ── Botón calcular ──
  const btnCalc = document.getElementById('btn-calcular');
  if (btnCalc) {
    btnCalc.addEventListener('click', onCalcular);
  }

  // ── Botón nueva consulta ──
  const btnNueva = document.getElementById('btn-nueva');
  if (btnNueva) {
    btnNueva.addEventListener('click', onNuevaConsulta);
  }

  // ── Atajo de teclado: Enter en cualquier input ejecuta cálculo ──
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const active = document.activeElement;
      const isInput = active && (active.tagName === 'INPUT' || active.tagName === 'SELECT');
      if (isInput) onCalcular();
    }
  });

  // Estado inicial de la caja 3D
  Preview3D.update(null, null, null);
}

// Espera a que el DOM esté listo
document.addEventListener('DOMContentLoaded', init);

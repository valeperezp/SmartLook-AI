import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { VentasService } from '../../../core/services/ventas.service';
import { AuthService } from '../../../core/services/auth.service';
import { Venta } from '../../../core/models/venta.model';
import { IconComponent } from '../../../core/components/icon/icon';

@Component({
  selector: 'app-ventas-historial',
  standalone: true,
  imports: [CommonModule, DatePipe, FormsModule, IconComponent],
  templateUrl: './ventas-historial.html',
  styleUrl: './ventas-historial.scss',
})
export class VentasHistorial implements OnInit {
  private ventasService = inject(VentasService);
  private auth = inject(AuthService);

  user = this.auth.currentUser;

  ventas = signal<Venta[]>([]);
  cargando = signal<boolean>(true);
  filtroEstado = signal<string>('todas');
  busqueda = signal<string>('');
  ventaSeleccionada = signal<Venta | null>(null);

  ventasFiltradas = computed(() => {
    const estado = this.filtroEstado();
    const q = this.busqueda().toLowerCase().trim();

    return this.ventas().filter((v) => {
      const matchEstado = estado === 'todas' || v.estado === estado;
      const matchQuery =
        !q ||
        String(v.id).includes(q) ||
        (v.nombre_cliente && v.nombre_cliente.toLowerCase().includes(q)) ||
        (v.nombre_cajero && v.nombre_cajero.toLowerCase().includes(q));
      return matchEstado && matchQuery;
    });
  });

  totalVentasMonto = computed(() => {
    return this.ventasFiltradas()
      .filter((v) => v.estado === 'completada')
      .reduce((sum, v) => sum + Number(v.total), 0);
  });

  totalVentasCantidad = computed(() => {
    return this.ventasFiltradas().length;
  });

  ngOnInit() {
    this.cargarVentas();
  }

  cargarVentas() {
    this.cargando.set(true);
    const sucursalId = this.user()?.sucursal_id || 1;
    this.ventasService.listarPorSucursal(sucursalId).subscribe({
      next: (data) => {
        this.ventas.set(data);
        this.cargando.set(false);
      },
      error: () => {
        this.cargando.set(false);
      },
    });
  }

  verDetalle(venta: Venta) {
    this.ventaSeleccionada.set(venta);
  }

  cerrarDetalle() {
    this.ventaSeleccionada.set(null);
  }
}

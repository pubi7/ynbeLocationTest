/**
 * AgentLocationsMap - Мобайл хэрэглэгчдийн (борлуулагчдын) байршил + мобайлаас хийсэн захиалгуудыг
 * дэлгүүр/харилцагчийн locationLatitude, locationLongitude-аар газар дээр харуулна
 *
 * Mobile app → Backend (POST /api/agents/:id/location) → GET /api/agents/locations/all
 * Mobile app → createOrder → GET /api/orders (customer.locationLatitude/Longitude)
 */
import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { MapPin, RefreshCw, Loader2, User, ShoppingCart } from 'lucide-react';
import api from '@/api/axios';

interface AgentLocationPoint {
  id: number;
  latitude: number;
  longitude: number;
  timestamp: string;
}

interface AgentWithLocations {
  agent: {
    id: number;
    name: string;
    email: string;
    role: string;
  };
  locations: AgentLocationPoint[];
}

interface OrderWithLocation {
  id: number;
  orderNumber?: string;
  totalAmount?: number;
  orderDate?: string;
  customer?: {
    name: string;
    locationLatitude?: number;
    locationLongitude?: number;
    address?: string;
  };
  agent?: { name: string };
  createdBy?: { name: string };
  /** getTinInfo-аас ирсэн мэдээлэл - Байгуулга сонгосон үед */
  ebarimtTin?: string;
  ebarimtRegNo?: string;
  ebarimtOrgName?: string;
}

export const AgentLocationsMap: React.FC = () => {
  const { toast } = useToast();
  const [loading, setLoading] = useState(true);
  const [agents, setAgents] = useState<AgentWithLocations[]>([]);
  const [orders, setOrders] = useState<OrderWithLocation[]>([]);
  const [selectedDate, setSelectedDate] = useState<string>(
    new Date().toISOString().split('T')[0]
  );

  const fetchAgentLocations = async () => {
    setLoading(true);
    try {
      const [agentsRes, ordersRes] = await Promise.all([
        api.get('/agents/locations/all', { params: { date: selectedDate } }),
        api.get('/orders', {
          params: {
            limit: 'all',
            startDate: selectedDate,
            endDate: (() => {
              const d = new Date(selectedDate);
              d.setDate(d.getDate() + 1);
              return d.toISOString().split('T')[0];
            })(),
          },
        }),
      ]);
      if (agentsRes.data.status === 'success') {
        setAgents(agentsRes.data.data?.agents || []);
      }
      if (ordersRes.data.status === 'success' || ordersRes.data.data?.orders) {
        const rawOrders = ordersRes.data.data?.orders || ordersRes.data.orders || [];
        const withLocation = rawOrders.filter(
          (o: OrderWithLocation) =>
            o.customer?.locationLatitude != null &&
            o.customer?.locationLongitude != null
        );
        setOrders(withLocation);
      }
    } catch (error: any) {
      toast({
        variant: 'destructive',
        title: 'Алдаа',
        description:
          error.response?.data?.message || 'Борлуулагчийн байршил татахад алдаа гарлаа',
      });
      setAgents([]);
      setOrders([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAgentLocations();
  }, [selectedDate]);

  const openInMaps = (lat: number, lng: number, label: string) => {
    const url = `https://www.google.com/maps?q=${lat},${lng}&z=17`;
    window.open(url, '_blank');
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <MapPin className="h-5 w-5" />
          Мобайл хэрэглэгчдийн байршил
        </CardTitle>
        <CardDescription>
          Борлуулагчид mobile app-аас байршил илгээж, мобайлаас хийсэн захиалгууд дэлгүүрийн байршил дээр харагдана. Огноо сонгоод шинэчлэнэ үү.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex gap-2 flex-wrap">
          <input
            type="date"
            value={selectedDate}
            onChange={(e) => setSelectedDate(e.target.value)}
            className="px-3 py-2 border rounded-md"
          />
          <Button onClick={fetchAgentLocations} disabled={loading}>
            {loading ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <RefreshCw className="h-4 w-4" />
            )}
            <span className="ml-2">Шинэчлэх</span>
          </Button>
        </div>

        {loading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : agents.length === 0 && orders.length === 0 ? (
          <p className="text-muted-foreground text-center py-8">
            Энэ өдрийн байршлын мэдээлэл эсвэл захиалга байхгүй байна.
          </p>
        ) : (
          <div className="space-y-6">
            {orders.length > 0 && (
              <div>
                <h4 className="font-medium flex items-center gap-2 mb-3">
                  <ShoppingCart className="h-4 w-4" />
                  Мобайлаас хийсэн захиалгууд (дэлгүүрийн байршил)
                </h4>
                <div className="space-y-3">
                  {orders.map((order) => {
                    const lat = order.customer?.locationLatitude;
                    const lng = order.customer?.locationLongitude;
                    if (lat == null || lng == null) return null;
                    return (
                      <div
                        key={order.id}
                        className="p-4 border rounded-lg hover:bg-muted/50 transition-colors"
                      >
                        <div className="flex items-start gap-3">
                          <div className="rounded-full bg-emerald-500/10 p-2">
                            <ShoppingCart className="h-5 w-5 text-emerald-600" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="font-medium">
                              {order.orderNumber || `#${order.id}`} • {order.customer?.name}
                            </div>
                            <div className="text-sm text-muted-foreground">
                              {order.totalAmount != null &&
                                `${Number(order.totalAmount).toLocaleString()} ₮`}
                              {(order.agent?.name || order.createdBy?.name) &&
                                ` • ${order.agent?.name || order.createdBy?.name}`}
                            </div>
                            <div className="text-xs text-muted-foreground mt-1">
                              {order.orderDate &&
                                new Date(order.orderDate).toLocaleString('mn-MN')}
                            </div>
                            {(order.ebarimtTin || order.ebarimtOrgName) && (
                              <div className="text-sm text-emerald-700 mt-2 space-y-0.5 bg-emerald-50 px-2 py-1.5 rounded border border-emerald-200">
                                <div className="font-medium">getTinInfo (Байгуулга):</div>
                                {order.ebarimtOrgName && <div>Нэр: {order.ebarimtOrgName}</div>}
                                {order.ebarimtTin && <div>TIN: {order.ebarimtTin}</div>}
                                {order.ebarimtRegNo && <div>Регистр: {order.ebarimtRegNo}</div>}
                              </div>
                            )}
                            <div className="text-sm mt-2">
                              📍 {lat.toFixed(6)}, {lng.toFixed(6)}
                            </div>
                            <Button
                              variant="outline"
                              size="sm"
                              className="mt-2"
                              onClick={() =>
                                openInMaps(lat, lng, order.customer?.name || 'Захиалга')
                              }
                            >
                              <MapPin className="h-4 w-4 mr-1" />
                              Газрын зураг дээр нээх
                            </Button>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
            {agents.length > 0 && (
              <div>
                <h4 className="font-medium flex items-center gap-2 mb-3">
                  <User className="h-4 w-4" />
                  Борлуулагчийн байршил
                </h4>
                <div className="space-y-4">
            {agents.map((item) => {
              const latest = item.locations[0];
              if (!latest) return null;
              return (
                <div
                  key={item.agent.id}
                  className="p-4 border rounded-lg hover:bg-muted/50 transition-colors"
                >
                  <div className="flex items-start gap-3">
                    <div className="rounded-full bg-primary/10 p-2">
                      <User className="h-5 w-5 text-primary" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-medium">{item.agent.name}</div>
                      <div className="text-sm text-muted-foreground">
                        {item.agent.email} • {item.locations.length} цэг
                      </div>
                      <div className="text-xs text-muted-foreground mt-1">
                        Сүүлд: {new Date(latest.timestamp).toLocaleString('mn-MN')}
                      </div>
                      <div className="text-sm mt-2">
                        📍 {latest.latitude.toFixed(6)}, {latest.longitude.toFixed(6)}
                      </div>
                      <Button
                        variant="outline"
                        size="sm"
                        className="mt-2"
                        onClick={() =>
                          openInMaps(
                            latest.latitude,
                            latest.longitude,
                            item.agent.name
                          )
                        }
                      >
                        <MapPin className="h-4 w-4 mr-1" />
                        Газрын зураг дээр нээх
                      </Button>
                    </div>
                  </div>
                </div>
              );
            })}
                </div>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};

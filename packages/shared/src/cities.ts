export interface CityInfo {
  name: string
  province: string
  country: string
}

const CITY_TABLE: Record<string, CityInfo> = {
  北京: { name: '北京', province: '北京', country: 'China' },
  北京市: { name: '北京', province: '北京', country: 'China' },
  上海: { name: '上海', province: '上海', country: 'China' },
  上海市: { name: '上海', province: '上海', country: 'China' },
  天津: { name: '天津', province: '天津', country: 'China' },
  天津市: { name: '天津', province: '天津', country: 'China' },
  重庆: { name: '重庆', province: '重庆', country: 'China' },
  重庆市: { name: '重庆', province: '重庆', country: 'China' },
  石家庄: { name: '石家庄', province: '河北', country: 'China' },
  唐山: { name: '唐山', province: '河北', country: 'China' },
  秦皇岛: { name: '秦皇岛', province: '河北', country: 'China' },
  邯郸: { name: '邯郸', province: '河北', country: 'China' },
  保定: { name: '保定', province: '河北', country: 'China' },
  太原: { name: '太原', province: '山西', country: 'China' },
  大同: { name: '大同', province: '山西', country: 'China' },
  呼和浩特: { name: '呼和浩特', province: '内蒙古', country: 'China' },
  包头: { name: '包头', province: '内蒙古', country: 'China' },
  沈阳: { name: '沈阳', province: '辽宁', country: 'China' },
  大连: { name: '大连', province: '辽宁', country: 'China' },
  鞍山: { name: '鞍山', province: '辽宁', country: 'China' },
  长春: { name: '长春', province: '吉林', country: 'China' },
  吉林: { name: '吉林', province: '吉林', country: 'China' },
  哈尔滨: { name: '哈尔滨', province: '黑龙江', country: 'China' },
  齐齐哈尔: { name: '齐齐哈尔', province: '黑龙江', country: 'China' },
  南京: { name: '南京', province: '江苏', country: 'China' },
  苏州: { name: '苏州', province: '江苏', country: 'China' },
  无锡: { name: '无锡', province: '江苏', country: 'China' },
  常州: { name: '常州', province: '江苏', country: 'China' },
  徐州: { name: '徐州', province: '江苏', country: 'China' },
  南通: { name: '南通', province: '江苏', country: 'China' },
  扬州: { name: '扬州', province: '江苏', country: 'China' },
  杭州: { name: '杭州', province: '浙江', country: 'China' },
  宁波: { name: '宁波', province: '浙江', country: 'China' },
  温州: { name: '温州', province: '浙江', country: 'China' },
  嘉兴: { name: '嘉兴', province: '浙江', country: 'China' },
  绍兴: { name: '绍兴', province: '浙江', country: 'China' },
  金华: { name: '金华', province: '浙江', country: 'China' },
  合肥: { name: '合肥', province: '安徽', country: 'China' },
  芜湖: { name: '芜湖', province: '安徽', country: 'China' },
  福州: { name: '福州', province: '福建', country: 'China' },
  厦门: { name: '厦门', province: '福建', country: 'China' },
  泉州: { name: '泉州', province: '福建', country: 'China' },
  南昌: { name: '南昌', province: '江西', country: 'China' },
  赣州: { name: '赣州', province: '江西', country: 'China' },
  济南: { name: '济南', province: '山东', country: 'China' },
  青岛: { name: '青岛', province: '山东', country: 'China' },
  淄博: { name: '淄博', province: '山东', country: 'China' },
  烟台: { name: '烟台', province: '山东', country: 'China' },
  潍坊: { name: '潍坊', province: '山东', country: 'China' },
  威海: { name: '威海', province: '山东', country: 'China' },
  郑州: { name: '郑州', province: '河南', country: 'China' },
  洛阳: { name: '洛阳', province: '河南', country: 'China' },
  开封: { name: '开封', province: '河南', country: 'China' },
  武汉: { name: '武汉', province: '湖北', country: 'China' },
  宜昌: { name: '宜昌', province: '湖北', country: 'China' },
  长沙: { name: '长沙', province: '湖南', country: 'China' },
  株洲: { name: '株洲', province: '湖南', country: 'China' },
  广州: { name: '广州', province: '广东', country: 'China' },
  深圳: { name: '深圳', province: '广东', country: 'China' },
  珠海: { name: '珠海', province: '广东', country: 'China' },
  东莞: { name: '东莞', province: '广东', country: 'China' },
  佛山: { name: '佛山', province: '广东', country: 'China' },
  惠州: { name: '惠州', province: '广东', country: 'China' },
  南宁: { name: '南宁', province: '广西', country: 'China' },
  桂林: { name: '桂林', province: '广西', country: 'China' },
  海口: { name: '海口', province: '海南', country: 'China' },
  三亚: { name: '三亚', province: '海南', country: 'China' },
  成都: { name: '成都', province: '四川', country: 'China' },
  绵阳: { name: '绵阳', province: '四川', country: 'China' },
  贵阳: { name: '贵阳', province: '贵州', country: 'China' },
  遵义: { name: '遵义', province: '贵州', country: 'China' },
  昆明: { name: '昆明', province: '云南', country: 'China' },
  大理: { name: '大理', province: '云南', country: 'China' },
  拉萨: { name: '拉萨', province: '西藏', country: 'China' },
  西安: { name: '西安', province: '陕西', country: 'China' },
  宝鸡: { name: '宝鸡', province: '陕西', country: 'China' },
  兰州: { name: '兰州', province: '甘肃', country: 'China' },
  西宁: { name: '西宁', province: '青海', country: 'China' },
  银川: { name: '银川', province: '宁夏', country: 'China' },
  乌鲁木齐: { name: '乌鲁木齐', province: '新疆', country: 'China' },
  香港: { name: '香港', province: '香港', country: 'China' },
  澳门: { name: '澳门', province: '澳门', country: 'China' },
  台北: { name: '台北', province: '台湾', country: 'China' },
  高雄: { name: '高雄', province: '台湾', country: 'China' },
  台中: { name: '台中', province: '台湾', country: 'China' },
  廊坊: { name: '廊坊', province: '河北', country: 'China' },
  沧州: { name: '沧州', province: '河北', country: 'China' },
  济宁: { name: '济宁', province: '山东', country: 'China' },
  临沂: { name: '临沂', province: '山东', country: 'China' },
  日照: { name: '日照', province: '山东', country: 'China' },
  聊城: { name: '聊城', province: '山东', country: 'China' },
  漳州: { name: '漳州', province: '福建', country: 'China' },
  柳州: { name: '柳州', province: '广西', country: 'China' },
  襄阳: { name: '襄阳', province: '湖北', country: 'China' },
  岳阳: { name: '岳阳', province: '湖南', country: 'China' },
  珠海市: { name: '珠海', province: '广东', country: 'China' },
  中山: { name: '中山', province: '广东', country: 'China' },
  汕头: { name: '汕头', province: '广东', country: 'China' },
  韶关: { name: '韶关', province: '广东', country: 'China' },
  湛江: { name: '湛江', province: '广东', country: 'China' },
  肇庆: { name: '肇庆', province: '广东', country: 'China' },
  江门: { name: '江门', province: '广东', country: 'China' },
  茂名: { name: '茂名', province: '广东', country: 'China' },
  梅州: { name: '梅州', province: '广东', country: 'China' },
  南平: { name: '南平', province: '福建', country: 'China' },
  龙岩: { name: '龙岩', province: '福建', country: 'China' },
  宁德: { name: '宁德', province: '福建', country: 'China' },
}

const SORTED_KEYS = Object.keys(CITY_TABLE).sort((a, b) => b.length - a.length)

export function extractCity(location: string | null): CityInfo | null {
  if (!location) return null
  for (const key of SORTED_KEYS) {
    if (location.includes(key)) return CITY_TABLE[key]
  }
  return null
}

export function getAllCities(): string[] {
  const seen = new Set<string>()
  const result: string[] = []
  for (const info of Object.values(CITY_TABLE)) {
    if (!seen.has(info.name)) {
      seen.add(info.name)
      result.push(info.name)
    }
  }
  return result
}

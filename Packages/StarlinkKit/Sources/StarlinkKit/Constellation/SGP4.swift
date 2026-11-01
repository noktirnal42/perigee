import Foundation

/// Near-earth SGP4 (Vallado's reference formulation, WGS-72 constants). Starlink orbits are all near-earth
/// (period < 225 min), so the deep-space branch is intentionally not implemented.
public struct SGP4Propagator: Sendable {
    // WGS-72
    static let re = 6378.135
    static let mu = 398600.8
    static let xke = 60.0 / (re * re * re / mu).squareRoot()
    static let j2 = 0.001082616, j3 = -0.00000253881, j4 = -0.00000165597
    static let j3oj2 = j3 / j2
    static let twoPi = 2 * Double.pi
    static let vkmps = re * xke / 60

    public let epoch: Date
    public let inclinationDeg: Double
    public let meanMotionRevPerDay: Double

    private let bstar, ecco, inclo, nodeo, argpo, mo, no: Double
    private let isimp: Bool
    private let con41, x1mth2, x7thm1, cc1, cc4, cc5, d2, d3, d4, delmo, eta, sinmao: Double
    private let t2cof, t3cof, t4cof, t5cof, omgcof, xmcof, nodecf: Double
    private let mdot, argpdot, nodedot, aycof, xlcof: Double

    public init?(epoch: Date, inclinationDeg: Double, raanDeg: Double, eccentricity: Double, argPerigeeDeg: Double,
                 meanAnomalyDeg: Double, meanMotionRevPerDay: Double, bstar: Double) {
        let d2r = Double.pi / 180
        self.epoch = epoch; self.inclinationDeg = inclinationDeg; self.meanMotionRevPerDay = meanMotionRevPerDay
        self.bstar = bstar; ecco = eccentricity; inclo = inclinationDeg * d2r; nodeo = raanDeg * d2r
        argpo = argPerigeeDeg * d2r; mo = meanAnomalyDeg * d2r
        let noKozai = meanMotionRevPerDay * Self.twoPi / 1440
        guard noKozai > 0, eccentricity >= 0, eccentricity < 0.7 else { return nil }
        // period > 225 min would need the deep-space model
        guard Self.twoPi / noKozai < 225 else { return nil }

        let xke = Self.xke, j2 = Self.j2, j3oj2 = Self.j3oj2, j4 = Self.j4, re = Self.re
        let ss = 78 / re + 1
        let qzms2t = pow((120 - 78) / re, 4)
        let cosio = cos(inclo), sinio = sin(inclo)
        let cosio2 = cosio * cosio
        let omeosq = 1 - ecco * ecco, rteosq = omeosq.squareRoot()
        // un-Kozai the mean motion
        let ak = pow(xke / noKozai, 2.0 / 3.0)
        let d1 = 0.75 * j2 * (3 * cosio2 - 1) / (rteosq * omeosq)
        var del = d1 / (ak * ak)
        let adel = ak * (1 - del * del - del * (1.0 / 3.0 + 134 * del * del / 81))
        del = d1 / (adel * adel)
        let no = noKozai / (1 + del)
        self.no = no
        let ao = pow(xke / no, 2.0 / 3.0)
        let po = ao * omeosq
        let con42 = 1 - 5 * cosio2
        con41 = -con42 - cosio2 - cosio2
        let posq = po * po
        let rp = ao * (1 - ecco)

        isimp = rp < 220 / re + 1
        let sfour = ss, qzms24 = qzms2t
        let pinvsq = 1 / posq
        let tsi = 1 / (ao - sfour)
        eta = ao * ecco * tsi
        let etasq = eta * eta, eeta = ecco * eta
        let psisq = abs(1 - etasq)
        let coef = qzms24 * pow(tsi, 4)
        let coef1 = coef / pow(psisq, 3.5)
        let cc2 = coef1 * no * (ao * (1 + 1.5 * etasq + eeta * (4 + etasq)) + 0.375 * j2 * tsi / psisq * con41 * (8 + 3 * etasq * (8 + etasq)))
        cc1 = bstar * cc2
        let cc3 = ecco > 1e-4 ? -2 * coef * tsi * j3oj2 * no * sinio / ecco : 0
        x1mth2 = 1 - cosio2
        cc4 = 2 * no * coef1 * ao * omeosq * (eta * (2 + 0.5 * etasq) + ecco * (0.5 + 2 * etasq)
              - j2 * tsi / (ao * psisq) * (-3 * con41 * (1 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
              + 0.75 * x1mth2 * (2 * etasq - eeta * (1 + etasq)) * cos(2 * argpo)))
        cc5 = 2 * coef1 * ao * omeosq * (1 + 2.75 * (etasq + eeta) + eeta * etasq)
        let cosio4 = cosio2 * cosio2
        let temp1 = 1.5 * j2 * pinvsq * no
        let temp2 = 0.5 * temp1 * j2 * pinvsq
        let temp3 = -0.46875 * j4 * pinvsq * pinvsq * no
        mdot = no + 0.5 * temp1 * rteosq * con41 + 0.0625 * temp2 * rteosq * (13 - 78 * cosio2 + 137 * cosio4)
        argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 * (7 - 114 * cosio2 + 395 * cosio4) + temp3 * (3 - 36 * cosio2 + 49 * cosio4)
        let xhdot1 = -temp1 * cosio
        nodedot = xhdot1 + (0.5 * temp2 * (4 - 19 * cosio2) + 2 * temp3 * (3 - 7 * cosio2)) * cosio
        omgcof = bstar * cc3 * cos(argpo)
        xmcof = ecco > 1e-4 ? -(2.0 / 3.0) * coef * bstar / eeta : 0
        nodecf = 3.5 * omeosq * xhdot1 * cc1
        t2cof = 1.5 * cc1
        xlcof = abs(cosio + 1) > 1.5e-12 ? -0.25 * j3oj2 * sinio * (3 + 5 * cosio) / (1 + cosio) : -0.25 * j3oj2 * sinio * (3 + 5 * cosio) / 1.5e-12
        aycof = -0.5 * j3oj2 * sinio
        let dm = 1 + eta * cos(mo)
        delmo = dm * dm * dm
        sinmao = sin(mo)
        x7thm1 = 7 * cosio2 - 1
        if !isimp {
            let cc1sq = cc1 * cc1
            d2 = 4 * ao * tsi * cc1sq
            let temp = d2 * tsi * cc1 / 3
            d3 = (17 * ao + sfour) * temp
            d4 = 0.5 * temp * ao * tsi * (221 * ao + 31 * sfour) * cc1
            t3cof = d2 + 2 * cc1sq
            t4cof = 0.25 * (3 * d3 + cc1 * (12 * d2 + 10 * cc1sq))
            t5cof = 0.2 * (3 * d4 + 12 * cc1 * d3 + 6 * d2 * d2 + 15 * cc1sq * (2 * d2 + cc1sq))
        } else { d2 = 0; d3 = 0; d4 = 0; t3cof = 0; t4cof = 0; t5cof = 0 }
    }

    /// Position (km) and velocity (km/s) in the TEME frame, `minutes` after the element epoch.
    public func propagate(minutes t: Double) -> (r: SIMD3<Double>, v: SIMD3<Double>)? {
        let xke = Self.xke, j2 = Self.j2
        let xmdf = mo + mdot * t, argpdf = argpo + argpdot * t, nodedf = nodeo + nodedot * t
        var argpm = argpdf, mm = xmdf
        let t2 = t * t
        var nodem = nodedf + nodecf * t2
        var tempa = 1 - cc1 * t, tempe = bstar * cc4 * t, templ = t2cof * t2
        if !isimp {
            let delomg = omgcof * t
            let dmt = 1 + eta * cos(xmdf)
            let delm = xmcof * (dmt * dmt * dmt - delmo)
            let temp = delomg + delm
            mm = xmdf + temp; argpm = argpdf - temp
            let t3 = t2 * t, t4 = t3 * t
            tempa = tempa - d2 * t2 - d3 * t3 - d4 * t4
            tempe += bstar * cc5 * (sin(mm) - sinmao)
            templ += t3cof * t3 + t4 * (t4cof + t * t5cof)
        }
        var nm = no, em = ecco
        let am = pow(xke / nm, 2.0 / 3.0) * tempa * tempa
        nm = xke / pow(am, 1.5)
        em -= tempe
        guard em < 1, em >= -0.001, am >= 0.95 else { return nil }
        if em < 1e-6 { em = 1e-6 }
        mm += no * templ
        var xlm = mm + argpm + nodem
        nodem = fmod(nodem, Self.twoPi); argpm = fmod(argpm, Self.twoPi); xlm = fmod(xlm, Self.twoPi)
        mm = fmod(xlm - argpm - nodem, Self.twoPi)
        let sinip = sin(inclo), cosip = cos(inclo)
        let ep = em, xincp = inclo, argpp = argpm, nodep = nodem, mp = mm

        let axnl = ep * cos(argpp)
        var temp = 1 / (am * (1 - ep * ep))
        let aynl = ep * sin(argpp) + temp * aycof
        let xl = mp + argpp + nodep + temp * xlcof * axnl
        let u = fmod(xl - nodep, Self.twoPi)
        var eo1 = u, tem5 = 9999.9
        var ktr = 1
        var sineo1 = 0.0, coseo1 = 0.0
        while abs(tem5) >= 1e-12 && ktr <= 10 {
            sineo1 = sin(eo1); coseo1 = cos(eo1)
            tem5 = 1 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if abs(tem5) >= 0.95 { tem5 = tem5 > 0 ? 0.95 : -0.95 }
            eo1 += tem5; ktr += 1
        }
        let ecose = axnl * coseo1 + aynl * sineo1, esine = axnl * sineo1 - aynl * coseo1
        let el2 = axnl * axnl + aynl * aynl
        let pl = am * (1 - el2)
        guard pl >= 0 else { return nil }
        let rl = am * (1 - ecose)
        let rdotl = am.squareRoot() * esine / rl
        let rvdotl = pl.squareRoot() / rl
        let betal = (1 - el2).squareRoot()
        temp = esine / (1 + betal)
        let sinu = am / rl * (sineo1 - aynl - axnl * temp)
        let cosu = am / rl * (coseo1 - axnl + aynl * temp)
        var su = atan2(sinu, cosu)
        let sin2u = (cosu + cosu) * sinu, cos2u = 1 - 2 * sinu * sinu
        temp = 1 / pl
        let temp1 = 0.5 * j2 * temp, temp2 = temp1 * temp

        let mrt = rl * (1 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
        su -= 0.25 * temp2 * x7thm1 * sin2u
        let xnode = nodep + 1.5 * temp2 * cosip * sin2u
        let xinc = xincp + 1.5 * temp2 * cosip * sinip * cos2u
        let mvt = rdotl - nm * temp1 * x1mth2 * sin2u / xke
        let rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u + 1.5 * con41) / xke

        let sinsu = sin(su), cossu = cos(su), snod = sin(xnode), cnod = cos(xnode), sini = sin(xinc), cosi = cos(xinc)
        let xmx = -snod * cosi, xmy = cnod * cosi
        let ux = xmx * sinsu + cnod * cossu, uy = xmy * sinsu + snod * cossu, uz = sini * sinsu
        let vx = xmx * cossu - cnod * sinsu, vy = xmy * cossu - snod * sinsu, vz = sini * cossu
        guard mrt >= 1 else { return nil }   // decayed
        let re = Self.re
        let r = SIMD3(mrt * ux, mrt * uy, mrt * uz) * re
        let v = SIMD3(mvt * ux + rvdot * vx, mvt * uy + rvdot * vy, mvt * uz + rvdot * vz) * Self.vkmps
        return (r, v)
    }
}

private func fmod(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

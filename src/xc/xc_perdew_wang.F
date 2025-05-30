!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Calculate the Perdew-Wang correlation potential and
!>      energy density and ist derivatives with respect to
!>      the spin-up and spin-down densities up to 3rd order.
!> \par History
!>      18-MAR-2002, TCH, working version
!>      fawzi (04.2004)  : adapted to the new xc interface
!> \see functionals_utilities
! **************************************************************************************************
MODULE xc_perdew_wang
   #:include "xc_perdew_wang.fypp"

   USE kinds, ONLY: dp
   USE pw_types, ONLY: pw_r3d_rs_type
   USE xc_derivative_set_types, ONLY: xc_derivative_set_type, &
                                      xc_dset_get_derivative
   USE xc_derivative_types, ONLY: xc_derivative_get, &
                                  xc_derivative_type
   USE xc_functionals_utilities, ONLY: calc_fx, &
                                       calc_rs, &
                                       calc_z, &
                                       set_util
   USE xc_input_constants, ONLY: pw_dmc, &
                                 pw_orig, &
                                 pw_vmc
   USE xc_rho_cflags_types, ONLY: xc_rho_cflags_type
   USE xc_rho_set_types, ONLY: xc_rho_set_get, &
                               xc_rho_set_type
   USE xc_derivative_desc, ONLY: deriv_rho, &
                                 deriv_rhoa, &
                                 deriv_rhob
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   @: global_var_pw92()
   REAL(KIND=dp), PARAMETER :: &
      epsilon = 5.E-13_dp, &
      fpp = 0.584822362263464620726223866376013788782_dp ! d^2f(0)/dz^2
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'xc_perdew_wang'

   PUBLIC :: perdew_wang_info, perdew_wang_lda_eval, perdew_wang_lsd_eval, perdew_wang_fxc_calc

CONTAINS

! **************************************************************************************************
!> \brief Return some info on the functionals.
!> \param method ...
!> \param lsd ...
!> \param reference full reference
!> \param shortform short reference
!> \param needs ...
!> \param max_deriv ...
!> \param scale ...
! **************************************************************************************************
   SUBROUTINE perdew_wang_info(method, lsd, reference, shortform, needs, &
                               max_deriv, scale)
      INTEGER, INTENT(in)                                :: method
      LOGICAL, INTENT(in)                                :: lsd
      CHARACTER(LEN=*), INTENT(OUT), OPTIONAL            :: reference, shortform
      TYPE(xc_rho_cflags_type), INTENT(inout), OPTIONAL  :: needs
      INTEGER, INTENT(out), OPTIONAL                     :: max_deriv
      REAL(kind=dp), INTENT(in)                          :: scale

      CHARACTER(len=3)                                   :: p_string

      SELECT CASE (method)
      CASE DEFAULT
         CPABORT("Unsupported parametrization")
      CASE (pw_orig)
         p_string = 'PWO'
      CASE (pw_dmc)
         p_string = 'DMC'
      CASE (pw_vmc)
         p_string = 'VMC'
      END SELECT

      IF (PRESENT(reference)) THEN
         reference = "J. P. Perdew and Yue Wang," &
                     //" Phys. Rev. B 45, 13244 (1992)" &
                     //"["//TRIM(p_string)//"]"
         IF (scale /= 1._dp) THEN
            WRITE (reference(LEN_TRIM(reference) + 1:LEN(reference)), "('s=',f5.3)") &
               scale
         END IF
         IF (.NOT. lsd) THEN
            IF (LEN_TRIM(reference) + 6 < LEN(reference)) THEN
               reference(LEN_TRIM(reference) + 1:LEN_TRIM(reference) + 7) = ' {LDA}'
            END IF
         END IF
      END IF
      IF (PRESENT(shortform)) THEN
         shortform = "J. P. Perdew et al., PRB 45, 13244 (1992)" &
                     //"["//TRIM(p_string)//"]"
         IF (scale /= 1._dp) THEN
            WRITE (shortform(LEN_TRIM(shortform) + 1:LEN(shortform)), "('s=',f5.3)") &
               scale
         END IF
         IF (.NOT. lsd) THEN
            IF (LEN_TRIM(shortform) + 6 < LEN(shortform)) THEN
               shortform(LEN_TRIM(shortform) + 1:LEN_TRIM(shortform) + 7) = ' {LDA}'
            END IF
         END IF
      END IF
      IF (PRESENT(needs)) THEN
         IF (lsd) THEN
            needs%rho_spin = .TRUE.
         ELSE
            needs%rho = .TRUE.
         END IF
      END IF
      IF (PRESENT(max_deriv)) max_deriv = 3

   END SUBROUTINE perdew_wang_info

   @: init_pw92()

! **************************************************************************************************
!> \brief Calculate the correlation energy and its derivatives
!>      wrt to rho (the electron density) up to 3rd order. This
!>      is the LDA version of the Perdew-Wang correlation energy
!>      If no order argument is given, then the routine calculates
!>      just the energy.
!> \param method ...
!> \param rho_set ...
!> \param deriv_set ...
!> \param order order of derivatives to calculate
!>      order must lie between -3 and 3. If it is negative then only
!>      that order will be calculated, otherwise all derivatives up to
!>      that order will be calculated.
!> \param scale ...
! **************************************************************************************************
   SUBROUTINE perdew_wang_lda_eval(method, rho_set, deriv_set, order, scale)

      INTEGER, INTENT(in)                                :: method
      TYPE(xc_rho_set_type), INTENT(IN)                  :: rho_set
      TYPE(xc_derivative_set_type), INTENT(IN)           :: deriv_set
      INTEGER, INTENT(in)                                :: order
      REAL(kind=dp), INTENT(in)                          :: scale

      CHARACTER(len=*), PARAMETER :: routineN = 'perdew_wang_lda_eval'

      INTEGER                                            :: npoints, timer_handle
      INTEGER, DIMENSION(2, 3)                  :: bo
      REAL(KIND=dp)                                      :: rho_cutoff
      REAL(KIND=dp), CONTIGUOUS, DIMENSION(:, :, :), POINTER         :: dummy, e_0, e_rho, e_rho_rho, &
                                                                        e_rho_rho_rho, rho
      TYPE(xc_derivative_type), POINTER                  :: deriv

      CALL timeset(routineN, timer_handle)
      NULLIFY (rho, e_0, e_rho, e_rho_rho, e_rho_rho_rho, dummy)
      CALL xc_rho_set_get(rho_set, rho=rho, &
                          local_bounds=bo, rho_cutoff=rho_cutoff)
      npoints = (bo(2, 1) - bo(1, 1) + 1)*(bo(2, 2) - bo(1, 2) + 1)*(bo(2, 3) - bo(1, 3) + 1)

      CALL perdew_wang_init(method, rho_cutoff)

      dummy => rho

      e_0 => dummy
      e_rho => dummy
      e_rho_rho => dummy
      e_rho_rho_rho => dummy

      IF (order >= 0) THEN
         deriv => xc_dset_get_derivative(deriv_set, [INTEGER::], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=e_0)
      END IF
      IF (order >= 1 .OR. order == -1) THEN
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rho], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=e_rho)
      END IF
      IF (order >= 2 .OR. order == -2) THEN
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rho, deriv_rho], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=e_rho_rho)
      END IF
      IF (order >= 3 .OR. order == -3) THEN
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rho, deriv_rho, deriv_rho], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=e_rho_rho_rho)
      END IF
      IF (order > 3 .OR. order < -3) THEN
         CPABORT("derivatives bigger than 3 not implemented")
      END IF

      CALL perdew_wang_lda_calc(rho, e_0, e_rho, e_rho_rho, e_rho_rho_rho, &
                                npoints, order, scale)

      CALL timestop(timer_handle)

   END SUBROUTINE perdew_wang_lda_eval

! **************************************************************************************************
!> \brief ...
!> \param rho ...
!> \param e_0 ...
!> \param e_rho ...
!> \param e_rho_rho ...
!> \param e_rho_rho_rho ...
!> \param npoints ...
!> \param order ...
!> \param scale ...
! **************************************************************************************************
   SUBROUTINE perdew_wang_lda_calc(rho, e_0, e_rho, e_rho_rho, e_rho_rho_rho, npoints, order, scale)
      !FM low level calc routine
      REAL(KIND=dp), DIMENSION(*), INTENT(in)            :: rho
      REAL(KIND=dp), DIMENSION(*), INTENT(inout)         :: e_0, e_rho, e_rho_rho, e_rho_rho_rho
      INTEGER, INTENT(in)                                :: npoints, order
      REAL(kind=dp), INTENT(in)                          :: scale

      INTEGER                                            :: abs_order, k
      REAL(KIND=dp), DIMENSION(0:3)                      :: ed

      abs_order = ABS(order)

!$OMP PARALLEL DO PRIVATE (k, ed) DEFAULT(NONE)&
!$OMP SHARED(npoints,rho,eps_rho,abs_order,scale,e_0,e_rho,e_rho_rho,e_rho_rho_rho,order)
      DO k = 1, npoints

         IF (rho(k) > eps_rho) THEN
!! order_ is positive as it must be in this case:
!! ec(:,2) needs ed(:,1) for example
            CALL pw_lda_ed_loc(rho(k), ed, abs_order)
            ed(0:abs_order) = scale*ed(0:abs_order)

            IF (order >= 0) THEN
               e_0(k) = e_0(k) + rho(k)*ed(0)
            END IF
            IF (order >= 1 .OR. order == -1) THEN
               e_rho(k) = e_rho(k) + ed(0) + rho(k)*ed(1)
            END IF
            IF (order >= 2 .OR. order == -2) THEN
               e_rho_rho(k) = e_rho_rho(k) + 2.0_dp*ed(1) + rho(k)*ed(2)
            END IF
            IF (order >= 3 .OR. order == -3) THEN
               e_rho_rho_rho(k) = e_rho_rho_rho(k) + 3.0_dp*ed(2) + rho(k)*ed(3)
            END IF

         END IF

      END DO
!$OMP END PARALLEL DO

   END SUBROUTINE perdew_wang_lda_calc

! **************************************************************************************************
!> \brief Calculate the correlation energy and its derivatives
!>      wrt to rho (the electron density) up to 3rd order. This
!>      is the LSD version of the Perdew-Wang correlation energy
!>      If no order argument is given, then the routine calculates
!>      just the energy.
!> \param method ...
!> \param rho_set ...
!> \param deriv_set ...
!> \param order order of derivatives to calculate
!>      order must lie between -3 and 3. If it is negative then only
!>      that order will be calculated, otherwise all derivatives up to
!>      that order will be calculated.
!> \param scale ...
! **************************************************************************************************
   SUBROUTINE perdew_wang_lsd_eval(method, rho_set, deriv_set, order, scale)
      INTEGER, INTENT(in)                                :: method
      TYPE(xc_rho_set_type), INTENT(IN)                  :: rho_set
      TYPE(xc_derivative_set_type), INTENT(IN)           :: deriv_set
      INTEGER, INTENT(IN), OPTIONAL                      :: order
      REAL(kind=dp), INTENT(in)                          :: scale

      CHARACTER(len=*), PARAMETER :: routineN = 'perdew_wang_lsd_eval'

      INTEGER                                            :: npoints, timer_handle
      INTEGER, DIMENSION(2, 3)                  :: bo
      REAL(KIND=dp)                                      :: rho_cutoff
      REAL(KIND=dp), CONTIGUOUS, DIMENSION(:, :, :), POINTER         :: a, b, dummy, e_0, ea, eaa, eaaa, eaab, &
                                                                        eab, eabb, eb, ebb, ebbb
      TYPE(xc_derivative_type), POINTER                  :: deriv

      CALL timeset(routineN, timer_handle)
      NULLIFY (a, b, e_0, ea, eb, eaa, eab, ebb, eaaa, eaab, eabb, ebbb)
      CALL xc_rho_set_get(rho_set, rhoa=a, rhob=b, &
                          local_bounds=bo, rho_cutoff=rho_cutoff)
      npoints = (bo(2, 1) - bo(1, 1) + 1)*(bo(2, 2) - bo(1, 2) + 1)*(bo(2, 3) - bo(1, 3) + 1)

      CALL perdew_wang_init(method, rho_cutoff)

      ! meaningful default for the arrays we don't need: let us make compiler
      ! and debugger happy...
      dummy => a

      e_0 => dummy
      ea => dummy; eb => dummy
      eaa => dummy; eab => dummy; ebb => dummy
      eaaa => dummy; eaab => dummy; eabb => dummy; ebbb => dummy

      IF (order >= 0) THEN
         deriv => xc_dset_get_derivative(deriv_set, [INTEGER::], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=e_0)
      END IF
      IF (order >= 1 .OR. order == -1) THEN
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhoa], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=ea)
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhob], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=eb)
      END IF
      IF (order >= 2 .OR. order == -2) THEN
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhoa, deriv_rhoa], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=eaa)
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhoa, deriv_rhob], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=eab)
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhob, deriv_rhob], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=ebb)
      END IF
      IF (order >= 3 .OR. order == -3) THEN
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhoa, deriv_rhoa, deriv_rhoa], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=eaaa)
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhoa, deriv_rhoa, deriv_rhob], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=eaab)
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhoa, deriv_rhob, deriv_rhob], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=eabb)
         deriv => xc_dset_get_derivative(deriv_set, [deriv_rhob, deriv_rhob, deriv_rhob], &
                                         allocate_deriv=.TRUE.)
         CALL xc_derivative_get(deriv, deriv_data=ebbb)
      END IF
      IF (order > 3 .OR. order < -3) THEN
         CPABORT("derivatives bigger than 3 not implemented")
      END IF

      CALL perdew_wang_lsd_calc(a, b, e_0, ea, eb, eaa, eab, ebb, eaaa, eaab, eabb, &
                                ebbb, npoints, order, scale)

      CALL timestop(timer_handle)

   END SUBROUTINE perdew_wang_lsd_eval

! **************************************************************************************************
!> \brief ...
!> \param rhoa ...
!> \param rhob ...
!> \param e_0 ...
!> \param ea ...
!> \param eb ...
!> \param eaa ...
!> \param eab ...
!> \param ebb ...
!> \param eaaa ...
!> \param eaab ...
!> \param eabb ...
!> \param ebbb ...
!> \param npoints ...
!> \param order ...
!> \param scale ...
! **************************************************************************************************
   SUBROUTINE perdew_wang_lsd_calc(rhoa, rhob, e_0, ea, eb, eaa, eab, ebb, eaaa, eaab, eabb, &
                                   ebbb, npoints, order, scale)
      !FM low-level computation routine
      REAL(KIND=dp), DIMENSION(*), INTENT(in)            :: rhoa, rhob
      REAL(KIND=dp), DIMENSION(*), INTENT(inout)         :: e_0, ea, eb, eaa, eab, ebb, eaaa, eaab, &
                                                            eabb, ebbb
      INTEGER, INTENT(in)                                :: npoints, order
      REAL(kind=dp), INTENT(in)                          :: scale

      INTEGER                                            :: abs_order, k
      REAL(KIND=dp)                                      :: rho
      REAL(KIND=dp), DIMENSION(0:9)                      :: ed

      abs_order = ABS(order)

!$OMP PARALLEL DO PRIVATE (k, rho, ed) DEFAULT(NONE)&
!$OMP SHARED(npoints,rhoa,rhob,eps_rho,abs_order,order,e_0,ea,eb,eaa,eab,ebb,eaaa,eaab,eabb,ebbb,scale)
      DO k = 1, npoints

         rho = rhoa(k) + rhob(k)
         IF (rho > eps_rho) THEN

            ed = 0.0_dp
            CALL pw_lsd_ed_loc(rhoa(k), rhob(k), ed, abs_order)
            ed = ed*scale

            IF (order >= 0) THEN
               e_0(k) = e_0(k) + rho*ed(0)
            END IF
            IF (order >= 1 .OR. order == -1) THEN
               ea(k) = ea(k) + ed(0) + rho*ed(1)
               eb(k) = eb(k) + ed(0) + rho*ed(2)
            END IF
            IF (order >= 2 .OR. order == -2) THEN
               eaa(k) = eaa(k) + 2.0_dp*ed(1) + rho*ed(3)
               eab(k) = eab(k) + ed(1) + ed(2) + rho*ed(4)
               ebb(k) = ebb(k) + 2.0_dp*ed(2) + rho*ed(5)
            END IF
            IF (order >= 3 .OR. order == -3) THEN
               eaaa(k) = eaaa(k) + 3.0_dp*ed(3) + rho*ed(6)
               eaab(k) = eaab(k) + 2.0_dp*ed(4) + ed(3) + rho*ed(7)
               eabb(k) = eabb(k) + 2.0_dp*ed(4) + ed(5) + rho*ed(8)
               ebbb(k) = ebbb(k) + 3.0_dp*ed(5) + rho*ed(9)
            END IF

         END IF

      END DO

   END SUBROUTINE perdew_wang_lsd_calc

! **************************************************************************************************
!> \brief ...
!> \param rho_a ...
!> \param rho_b ...
!> \param fxc_aa ...
!> \param fxc_ab ...
!> \param fxc_bb ...
!> \param scalec ...
!> \param eps_rho ...
! **************************************************************************************************
   SUBROUTINE perdew_wang_fxc_calc(rho_a, rho_b, fxc_aa, fxc_ab, fxc_bb, scalec, eps_rho)
      TYPE(pw_r3d_rs_type), INTENT(IN)                          :: rho_a, rho_b
      TYPE(pw_r3d_rs_type), INTENT(INOUT)                       :: fxc_aa, fxc_ab, fxc_bb
      REAL(kind=dp), INTENT(in)                          :: scalec, eps_rho

      INTEGER                                            :: i, j, k
      INTEGER, DIMENSION(2, 3)                           :: bo
      REAL(KIND=dp)                                      :: rho, rhoa, rhob, eaa, eab, ebb
      REAL(KIND=dp), DIMENSION(0:9)                      :: ed

      CALL perdew_wang_init(pw_orig, eps_rho)
      bo(1:2, 1:3) = rho_a%pw_grid%bounds_local(1:2, 1:3)
!$OMP PARALLEL DO PRIVATE(i,j,k,rho,rhoa,rhob,ed,eaa,eab,ebb) DEFAULT(NONE)&
!$OMP SHARED(bo,rho_a,rho_b,fxc_aa,fxc_ab,fxc_bb,scalec,eps_rho)
      DO k = bo(1, 3), bo(2, 3)
         DO j = bo(1, 2), bo(2, 2)
            DO i = bo(1, 1), bo(2, 1)
               rhoa = rho_a%array(i, j, k)
               rhob = rho_b%array(i, j, k)
               rho = rhoa + rhob
               IF (rho > eps_rho) THEN
                  ed = 0.0_dp
                  CALL pw_lsd_ed_loc(rhoa, rhob, ed, 2)
                  ed = ed*scalec
                  eaa = 2.0_dp*ed(1) + rho*ed(3)
                  eab = ed(1) + ed(2) + rho*ed(4)
                  ebb = 2.0_dp*ed(2) + rho*ed(5)
                  fxc_aa%array(i, j, k) = fxc_aa%array(i, j, k) + eaa
                  fxc_ab%array(i, j, k) = fxc_ab%array(i, j, k) + eab
                  fxc_bb%array(i, j, k) = fxc_bb%array(i, j, k) + ebb
               END IF
            END DO
         END DO
      END DO

   END SUBROUTINE perdew_wang_fxc_calc

   @:calc_g()

! **************************************************************************************************
!> \brief ...
!> \param rho ...
!> \param ed ...
!> \param order ...
! **************************************************************************************************
   SUBROUTINE pw_lda_ed_loc(rho, ed, order)

      REAL(KIND=dp), INTENT(IN)                          :: rho
      REAL(KIND=dp), DIMENSION(0:), INTENT(OUT)          :: ed
      INTEGER, INTENT(IN)                                :: order

      INTEGER                                            :: m, order_
      LOGICAL, DIMENSION(0:3)                            :: calc
      REAL(KIND=dp), DIMENSION(0:3)                      :: e0, r

      order_ = order
      ed = 0
      calc = .FALSE.

      IF (order_ >= 0) THEN
         calc(0:order_) = .TRUE.
      ELSE
         order_ = -1*order_
         calc(order_) = .TRUE.
      END IF

      CALL calc_rs(rho, r(0))
      CALL calc_g(r(0), 0, e0, order_)

      IF (order_ >= 1) r(1) = (-1.0_dp/3.0_dp)*r(0)/rho
      IF (order_ >= 2) r(2) = (-4.0_dp/3.0_dp)*r(1)/rho
      IF (order_ >= 3) r(3) = (-7.0_dp/3.0_dp)*r(2)/rho

      m = 0
      IF (calc(0)) THEN
         ed(m) = e0(0)
         m = m + 1
      END IF
      IF (calc(1)) THEN
         ed(m) = e0(1)*r(1)
         m = m + 1
      END IF
      IF (calc(2)) THEN
         ed(m) = e0(2)*r(1)**2 + e0(1)*r(2)
         m = m + 1
      END IF
      IF (calc(3)) THEN
         ed(m) = e0(3)*r(1)**3 + e0(2)*3.0_dp*r(1)*r(2) + e0(1)*r(3)
      END IF

   END SUBROUTINE pw_lda_ed_loc

! **************************************************************************************************
!> \brief ...
!> \param a ...
!> \param b ...
!> \param ed ...
!> \param order ...
! **************************************************************************************************
   SUBROUTINE pw_lsd_ed_loc(a, b, ed, order)

      REAL(KIND=dp), INTENT(IN)                          :: a, b
      REAL(KIND=dp), DIMENSION(0:), INTENT(OUT)          :: ed
      INTEGER, INTENT(IN)                                :: order

      INTEGER                                            :: m, order_
      LOGICAL, DIMENSION(0:3)                            :: calc
      REAL(KIND=dp)                                      :: rho, tr, trr, trrr, trrz, trz, trzz, tz, &
                                                            tzz, tzzz
      REAL(KIND=dp), DIMENSION(0:3)                      :: ac, e0, e1, f, r
      REAL(KIND=dp), DIMENSION(0:3, 0:3)                 :: z

      order_ = order
      calc = .FALSE.

      IF (order_ > 0) THEN
         calc(0:order_) = .TRUE.
      ELSE
         order_ = -1*order_
         calc(order_) = .TRUE.
      END IF

      rho = a + b

      CALL calc_fx(a, b, f(0:order_), order_)
      CALL calc_rs(rho, r(0))
      CALL calc_g(r(0), -1, ac(0:order_), order_)
      CALL calc_g(r(0), 0, e0(0:order_), order_)
      CALL calc_g(r(0), 1, e1(0:order_), order_)
      CALL calc_z(a, b, z(0:order_, 0:order_), order_)

!! calculate first partial derivatives
      IF (order_ >= 1) THEN
         r(1) = (-1.0_dp/3.0_dp)*r(0)/rho
         tr = e0(1) &
              + fpp*ac(1)*f(0) &
              - fpp*ac(1)*f(0)*z(0, 0)**4 &
              + (e1(1) - e0(1))*f(0)*z(0, 0)**4
         tz = fpp*ac(0)*f(1) &
              - fpp*ac(0)*f(1)*z(0, 0)**4 &
              - fpp*ac(0)*f(0)*4.0_dp*z(0, 0)**3 &
              + (e1(0) - e0(0))*f(1)*z(0, 0)**4 &
              + (e1(0) - e0(0))*f(0)*4.0_dp*z(0, 0)**3
      END IF

!! calculate second partial derivatives
      IF (order_ >= 2) THEN
         r(2) = (-4.0_dp/3.0_dp)*r(1)/rho
         trr = e0(2) &
               + fpp*ac(2)*f(0) &
               - fpp*ac(2)*f(0)*z(0, 0)**4 &
               + (e1(2) - e0(2))*f(0)*z(0, 0)**4
         trz = fpp*ac(1)*f(1) &
               - fpp*ac(1)*f(1)*z(0, 0)**4 &
               - fpp*ac(1)*f(0)*4.0_dp*z(0, 0)**3 &
               + (e1(1) - e0(1))*f(1)*z(0, 0)**4 &
               + (e1(1) - e0(1))*f(0)*4.0_dp*z(0, 0)**3
         tzz = fpp*ac(0)*f(2) &
               - fpp*ac(0)*f(2)*z(0, 0)**4 &
               - fpp*ac(0)*f(1)*8.0_dp*z(0, 0)**3 &
               - fpp*ac(0)*f(0)*12.0_dp*z(0, 0)**2 &
               + (e1(0) - e0(0))*f(2)*z(0, 0)**4 &
               + (e1(0) - e0(0))*f(1)*8.0_dp*z(0, 0)**3 &
               + (e1(0) - e0(0))*f(0)*12.0_dp*z(0, 0)**2
      END IF

!! calculate third derivatives
      IF (order_ >= 3) THEN

         r(3) = (-7.0_dp/3.0_dp)*r(2)/rho

         trrr = e0(3) &
                + fpp*ac(3)*f(0) &
                - fpp*ac(3)*f(0)*z(0, 0)**4 &
                + (e1(3) - e0(3))*f(0)*z(0, 0)**4

         trrz = fpp*ac(2)*f(1) &
                - fpp*ac(2)*f(1)*z(0, 0)**4 &
                - fpp*ac(2)*f(0)*4.0_dp*z(0, 0)**3 &
                + (e1(2) - e0(2))*f(1)*z(0, 0)**4 &
                + (e1(2) - e0(2))*f(0)*4.0_dp*z(0, 0)**3

         trzz = fpp*ac(1)*f(2) &
                - fpp*ac(1)*f(2)*z(0, 0)**4 &
                - fpp*ac(1)*f(1)*8.0_dp*z(0, 0)**3 &
                - fpp*ac(1)*f(0)*12.0_dp*z(0, 0)**2 &
                + (e1(1) - e0(1))*f(2)*z(0, 0)**4 &
                + (e1(1) - e0(1))*f(1)*8.0_dp*z(0, 0)**3 &
                + (e1(1) - e0(1))*f(0)*12.0_dp*z(0, 0)**2

         tzzz = fpp*ac(0)*f(3) &
                - fpp*ac(0)*f(3)*z(0, 0)**4 &
                - fpp*ac(0)*f(2)*12.0_dp*z(0, 0)**3 &
                - fpp*ac(0)*f(1)*36.0_dp*z(0, 0)**2 &
                - fpp*ac(0)*f(0)*24.0_dp*z(0, 0) &
                + (e1(0) - e0(0))*f(3)*z(0, 0)**4 &
                + (e1(0) - e0(0))*f(2)*12.0_dp*z(0, 0)**3 &
                + (e1(0) - e0(0))*f(1)*36.0_dp*z(0, 0)**2 &
                + (e1(0) - e0(0))*f(0)*24.0_dp*z(0, 0)
      END IF

      m = 0
      IF (calc(0)) THEN
         ed(m) = e0(0) &
                 + fpp*ac(0)*f(0)*(1.0_dp - z(0, 0)**4) &
                 + (e1(0) - e0(0))*f(0)*z(0, 0)**4
         m = m + 1
      END IF
      IF (calc(1)) THEN
         ed(m) = tr*r(1) + tz*z(1, 0)
         ed(m + 1) = tr*r(1) + tz*z(0, 1)
         m = m + 2
      END IF
      IF (calc(2)) THEN
         ed(m) = trr*r(1)**2 + 2.0_dp*trz*r(1)*z(1, 0) &
                 + tr*r(2) + tzz*z(1, 0)**2 + tz*z(2, 0)
         ed(m + 1) = trr*r(1)**2 + trz*r(1)*(z(0, 1) + z(1, 0)) &
                     + tr*r(2) + tzz*z(1, 0)*z(0, 1) + tz*z(1, 1)
         ed(m + 2) = trr*r(1)**2 + 2.0_dp*trz*r(1)*z(0, 1) &
                     + tr*r(2) + tzz*z(0, 1)**2 + tz*z(0, 2)
         m = m + 3
      END IF
      IF (calc(3)) THEN
         ed(m) = &
            trrr*r(1)**3 + 3.0_dp*trrz*r(1)**2*z(1, 0) &
            + 3.0_dp*trr*r(1)*r(2) + 3.0_dp*trz*r(2)*z(1, 0) + tr*r(3) &
            + 3.0_dp*trzz*r(1)*z(1, 0)**2 + tzzz*z(1, 0)**3 &
            + 3.0_dp*trz*r(1)*z(2, 0) &
            + 3.0_dp*tzz*z(1, 0)*z(2, 0) + tz*z(3, 0)
         ed(m + 1) = &
            trrr*r(1)**3 + trrz*r(1)**2*(2.0_dp*z(1, 0) + z(0, 1)) &
            + 2.0_dp*trzz*r(1)*z(1, 0)*z(0, 1) &
            + 2.0_dp*trz*(r(2)*z(1, 0) + r(1)*z(1, 1)) &
            + 3.0_dp*trr*r(2)*r(1) + trz*r(2)*z(0, 1) + tr*r(3) &
            + trzz*r(1)*z(1, 0)**2 + tzzz*z(1, 0)**2*z(0, 1) &
            + 2.0_dp*tzz*z(1, 0)*z(1, 1) &
            + trz*r(1)*z(2, 0) + tzz*z(2, 0)*z(0, 1) + tz*z(2, 1)
         ed(m + 2) = &
            trrr*r(1)**3 + trrz*r(1)**2*(2.0_dp*z(0, 1) + z(1, 0)) &
            + 2.0_dp*trzz*r(1)*z(0, 1)*z(1, 0) &
            + 2.0_dp*trz*(r(2)*z(0, 1) + r(1)*z(1, 1)) &
            + 3.0_dp*trr*r(2)*r(1) + trz*r(2)*z(1, 0) + tr*r(3) &
            + trzz*r(1)*z(0, 1)**2 + tzzz*z(0, 1)**2*z(1, 0) &
            + 2.0_dp*tzz*z(0, 1)*z(1, 1) &
            + trz*r(1)*z(0, 2) + tzz*z(0, 2)*z(1, 0) + tz*z(1, 2)
         ed(m + 3) = &
            trrr*r(1)**3 + 3.0_dp*trrz*r(1)**2*z(0, 1) &
            + 3.0_dp*trr*r(1)*r(2) + 3.0_dp*trz*r(2)*z(0, 1) + tr*r(3) &
            + 3.0_dp*trzz*r(1)*z(0, 1)**2 + tzzz*z(0, 1)**3 &
            + 3.0_dp*trz*r(1)*z(0, 2) &
            + 3.0_dp*tzz*z(0, 1)*z(0, 2) + tz*z(0, 3)
      END IF

   END SUBROUTINE pw_lsd_ed_loc

END MODULE xc_perdew_wang

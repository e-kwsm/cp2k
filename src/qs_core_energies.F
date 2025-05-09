!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Calculation of the energies concerning the core charge distribution
!> \par History
!>      - Full refactoring of calculate_ecore and calculate_ecore_overlap (jhu)
!> \author Matthias Krack (27.04.2001)
! **************************************************************************************************
MODULE qs_core_energies
   USE atomic_kind_types,               ONLY: atomic_kind_type,&
                                              get_atomic_kind,&
                                              get_atomic_kind_set
   USE atprop_types,                    ONLY: atprop_array_init,&
                                              atprop_type
   USE cell_types,                      ONLY: cell_type,&
                                              pbc
   USE cp_dbcsr_api,                    ONLY: dbcsr_p_type,&
                                              dbcsr_type
   USE cp_dbcsr_contrib,                ONLY: dbcsr_dot
   USE distribution_1d_types,           ONLY: distribution_1d_type
   USE kinds,                           ONLY: dp
   USE mathconstants,                   ONLY: oorootpi,&
                                              twopi
   USE message_passing,                 ONLY: mp_comm_type,&
                                              mp_para_env_type
   USE particle_types,                  ONLY: particle_type
   USE qs_energy_types,                 ONLY: qs_energy_type
   USE qs_environment_types,            ONLY: get_qs_env,&
                                              qs_environment_type
   USE qs_force_types,                  ONLY: qs_force_type
   USE qs_kind_types,                   ONLY: get_qs_kind,&
                                              qs_kind_type
   USE qs_neighbor_list_types,          ONLY: get_iterator_info,&
                                              neighbor_list_iterate,&
                                              neighbor_list_iterator_create,&
                                              neighbor_list_iterator_p_type,&
                                              neighbor_list_iterator_release,&
                                              neighbor_list_set_p_type
   USE virial_methods,                  ONLY: virial_pair_force
   USE virial_types,                    ONLY: virial_type
#include "./base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

! *** Global parameters ***

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_core_energies'

   PUBLIC :: calculate_ptrace, &
             calculate_ecore_overlap, &
             calculate_ecore_self, calculate_ecore_alpha

   INTERFACE calculate_ptrace
      MODULE PROCEDURE calculate_ptrace_1, calculate_ptrace_gamma, calculate_ptrace_kp
   END INTERFACE

! **************************************************************************************************

CONTAINS

! **************************************************************************************************
!> \brief  Calculate the trace of a operator matrix with the density matrix.
!>         Sum over all spin components (in P, no spin in H)
!> \param hmat ...
!> \param pmat ...
!> \param ecore ...
!> \param nspin ...
!> \date    29.07.2014
!> \par History
!>         - none
!> \author  JGH
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE calculate_ptrace_gamma(hmat, pmat, ecore, nspin)

      TYPE(dbcsr_p_type), DIMENSION(:), POINTER          :: hmat, pmat
      REAL(KIND=dp), INTENT(OUT)                         :: ecore
      INTEGER, INTENT(IN)                                :: nspin

      CHARACTER(len=*), PARAMETER :: routineN = 'calculate_ptrace_gamma'

      INTEGER                                            :: handle, ispin
      REAL(KIND=dp)                                      :: etr

      CALL timeset(routineN, handle)

      ecore = 0.0_dp
      DO ispin = 1, nspin
         etr = 0.0_dp
         CALL dbcsr_dot(hmat(1)%matrix, pmat(ispin)%matrix, etr)
         ecore = ecore + etr
      END DO

      CALL timestop(handle)

   END SUBROUTINE calculate_ptrace_gamma

! **************************************************************************************************
!> \brief  Calculate the trace of a operator matrix with the density matrix.
!>         Sum over all spin components (in P, no spin in H) and the real space
!>         coordinates
!> \param hmat    H matrix
!> \param pmat    P matrices
!> \param ecore   Tr(HP) output
!> \param nspin   Number of P matrices
!> \date    29.07.2014
!> \author  JGH
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE calculate_ptrace_kp(hmat, pmat, ecore, nspin)

      TYPE(dbcsr_p_type), DIMENSION(:, :), POINTER       :: hmat, pmat
      REAL(KIND=dp), INTENT(OUT)                         :: ecore
      INTEGER, INTENT(IN)                                :: nspin

      CHARACTER(len=*), PARAMETER :: routineN = 'calculate_ptrace_kp'

      INTEGER                                            :: handle, ic, ispin, nc
      REAL(KIND=dp)                                      :: etr

      CALL timeset(routineN, handle)

      nc = SIZE(pmat, 2)

      ecore = 0.0_dp
      DO ispin = 1, nspin
         DO ic = 1, nc
            etr = 0.0_dp
            CALL dbcsr_dot(hmat(1, ic)%matrix, pmat(ispin, ic)%matrix, etr)
            ecore = ecore + etr
         END DO
      END DO

      CALL timestop(handle)

   END SUBROUTINE calculate_ptrace_kp

! **************************************************************************************************
!> \brief  Calculate the core Hamiltonian energy which includes the kinetic
!>          and the potential energy of the electrons. It is assumed, that
!>          the core Hamiltonian matrix h and the density matrix p have the
!>          same sparse matrix structure (same atomic blocks and block
!>          ordering)
!> \param h ...
!> \param p ...
!> \param ecore ...
!> \date    03.05.2001
!> \par History
!>         - simplified taking advantage of new non-redundant matrix
!>           structure (27.06.2003,MK)
!>         - simplified using DBCSR trace function (21.07.2010, jhu)
!> \author  MK
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE calculate_ptrace_1(h, p, ecore)

      TYPE(dbcsr_type), POINTER                          :: h, p
      REAL(KIND=dp), INTENT(OUT)                         :: ecore

      CHARACTER(len=*), PARAMETER :: routineN = 'calculate_ptrace_1'

      INTEGER                                            :: handle

      CALL timeset(routineN, handle)

      ecore = 0.0_dp
      CALL dbcsr_dot(h, p, ecore)

      CALL timestop(handle)

   END SUBROUTINE calculate_ptrace_1

! **************************************************************************************************
!> \brief   Calculate the overlap energy of the core charge distribution.
!> \param qs_env ...
!> \param para_env ...
!> \param calculate_forces ...
!> \param molecular ...
!> \param E_overlap_core ...
!> \param atecc ...
!> \date    30.04.2001
!> \par History
!>       - Force calculation added (03.06.2002,MK)
!>       - Parallelized using a list of local atoms for rows and
!>         columns (19.07.2003,MK)
!>       - Use precomputed neighborlists (sab_core) and nl iterator (28.07.2010,jhu)
!> \author  MK
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE calculate_ecore_overlap(qs_env, para_env, calculate_forces, molecular, &
                                      E_overlap_core, atecc)
      TYPE(qs_environment_type), POINTER                 :: qs_env
      TYPE(mp_para_env_type), POINTER                    :: para_env
      LOGICAL, INTENT(IN)                                :: calculate_forces
      LOGICAL, INTENT(IN), OPTIONAL                      :: molecular
      REAL(KIND=dp), INTENT(OUT), OPTIONAL               :: E_overlap_core
      REAL(KIND=dp), DIMENSION(:), OPTIONAL              :: atecc

      CHARACTER(len=*), PARAMETER :: routineN = 'calculate_ecore_overlap'

      INTEGER                                            :: atom_a, atom_b, handle, iatom, ikind, &
                                                            jatom, jkind, natom, nkind
      INTEGER, ALLOCATABLE, DIMENSION(:)                 :: atom_of_kind
      LOGICAL                                            :: atenergy, only_molecule, use_virial
      REAL(KIND=dp)                                      :: aab, dab, eab, ecore_overlap, f, fab, &
                                                            rab2, rootaab, zab
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:)           :: alpha, radius, zeff
      REAL(KIND=dp), DIMENSION(3)                        :: deab, rab
      REAL(KIND=dp), DIMENSION(3, 3)                     :: pv_loc
      TYPE(atomic_kind_type), DIMENSION(:), POINTER      :: atomic_kind_set
      TYPE(atprop_type), POINTER                         :: atprop
      TYPE(mp_comm_type)                                 :: group
      TYPE(neighbor_list_iterator_p_type), &
         DIMENSION(:), POINTER                           :: nl_iterator
      TYPE(neighbor_list_set_p_type), DIMENSION(:), &
         POINTER                                         :: sab_core
      TYPE(particle_type), DIMENSION(:), POINTER         :: particle_set
      TYPE(qs_energy_type), POINTER                      :: energy
      TYPE(qs_force_type), DIMENSION(:), POINTER         :: force
      TYPE(qs_kind_type), DIMENSION(:), POINTER          :: qs_kind_set
      TYPE(virial_type), POINTER                         :: virial

      CALL timeset(routineN, handle)

      NULLIFY (atomic_kind_set)
      NULLIFY (qs_kind_set)
      NULLIFY (energy)
      NULLIFY (atprop)
      NULLIFY (force)
      NULLIFY (particle_set)

      group = para_env

      only_molecule = .FALSE.
      IF (PRESENT(molecular)) only_molecule = molecular

      CALL get_qs_env(qs_env=qs_env, &
                      atomic_kind_set=atomic_kind_set, &
                      qs_kind_set=qs_kind_set, &
                      particle_set=particle_set, &
                      energy=energy, &
                      force=force, &
                      sab_core=sab_core, &
                      atprop=atprop, &
                      virial=virial)

      ! Allocate work storage
      nkind = SIZE(atomic_kind_set)
      natom = SIZE(particle_set)

      use_virial = virial%pv_availability .AND. (.NOT. virial%pv_numer)

      ALLOCATE (alpha(nkind), radius(nkind), zeff(nkind))
      alpha(:) = 0.0_dp
      radius(:) = 0.0_dp
      zeff(:) = 0.0_dp

      IF (calculate_forces) THEN
         CALL get_atomic_kind_set(atomic_kind_set, atom_of_kind=atom_of_kind)
      END IF

      atenergy = .FALSE.
      IF (ASSOCIATED(atprop)) THEN
         IF (atprop%energy) THEN
            atenergy = .TRUE.
            CALL atprop_array_init(atprop%atecc, natom)
         END IF
      END IF

      DO ikind = 1, nkind
         CALL get_qs_kind(qs_kind_set(ikind), &
                          alpha_core_charge=alpha(ikind), &
                          core_charge_radius=radius(ikind), &
                          zeff=zeff(ikind))
      END DO

      ecore_overlap = 0.0_dp
      pv_loc = 0.0_dp

      CALL neighbor_list_iterator_create(nl_iterator, sab_core)
      DO WHILE (neighbor_list_iterate(nl_iterator) == 0)
         CALL get_iterator_info(nl_iterator, ikind=ikind, jkind=jkind, iatom=iatom, jatom=jatom, r=rab)
         zab = zeff(ikind)*zeff(jkind)
         aab = alpha(ikind)*alpha(jkind)/(alpha(ikind) + alpha(jkind))
         rootaab = SQRT(aab)
         fab = 2.0_dp*oorootpi*zab*rootaab
         rab2 = rab(1)*rab(1) + rab(2)*rab(2) + rab(3)*rab(3)
         IF (rab2 > 1.e-8_dp) THEN
            IF (ikind == jkind .AND. iatom == jatom) THEN
               f = 0.5_dp
            ELSE
               f = 1.0_dp
            END IF
            dab = SQRT(rab2)
            eab = zab*erfc(rootaab*dab)/dab
            ecore_overlap = ecore_overlap + f*eab
            IF (atenergy) THEN
               atprop%atecc(iatom) = atprop%atecc(iatom) + 0.5_dp*f*eab
               atprop%atecc(jatom) = atprop%atecc(jatom) + 0.5_dp*f*eab
            END IF
            IF (PRESENT(atecc)) THEN
               atecc(iatom) = atecc(iatom) + 0.5_dp*f*eab
               atecc(jatom) = atecc(jatom) + 0.5_dp*f*eab
            END IF
            IF (calculate_forces) THEN
               deab(:) = rab(:)*f*(eab + fab*EXP(-aab*rab2))/rab2
               atom_a = atom_of_kind(iatom)
               atom_b = atom_of_kind(jatom)
               force(ikind)%core_overlap(:, atom_a) = force(ikind)%core_overlap(:, atom_a) + deab(:)
               force(jkind)%core_overlap(:, atom_b) = force(jkind)%core_overlap(:, atom_b) - deab(:)
               IF (use_virial) THEN
                  CALL virial_pair_force(pv_loc, 1._dp, deab, rab)
               END IF
            END IF
         END IF
      END DO
      CALL neighbor_list_iterator_release(nl_iterator)

      DEALLOCATE (alpha, radius, zeff)
      IF (calculate_forces) THEN
         DEALLOCATE (atom_of_kind)
      END IF
      IF (calculate_forces .AND. use_virial) THEN
         virial%pv_ecore_overlap = virial%pv_ecore_overlap + pv_loc
         virial%pv_virial = virial%pv_virial + pv_loc
      END IF

      CALL group%sum(ecore_overlap)

      energy%core_overlap = ecore_overlap

      IF (PRESENT(E_overlap_core)) THEN
         E_overlap_core = energy%core_overlap
      END IF

      CALL timestop(handle)

   END SUBROUTINE calculate_ecore_overlap

! **************************************************************************************************
!> \brief   Calculate the self energy of the core charge distribution.
!> \param qs_env ...
!> \param E_self_core ...
!> \param atecc ...
!> \date    27.04.2001
!> \author  MK
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE calculate_ecore_self(qs_env, E_self_core, atecc)
      TYPE(qs_environment_type), POINTER                 :: qs_env
      REAL(KIND=dp), INTENT(OUT), OPTIONAL               :: E_self_core
      REAL(KIND=dp), DIMENSION(:), OPTIONAL              :: atecc

      CHARACTER(len=*), PARAMETER :: routineN = 'calculate_ecore_self'

      INTEGER                                            :: handle, iatom, ikind, iparticle_local, &
                                                            natom, nparticle_local
      REAL(KIND=dp)                                      :: alpha_core_charge, ecore_self, es, zeff
      TYPE(atomic_kind_type), DIMENSION(:), POINTER      :: atomic_kind_set
      TYPE(atprop_type), POINTER                         :: atprop
      TYPE(distribution_1d_type), POINTER                :: local_particles
      TYPE(particle_type), DIMENSION(:), POINTER         :: particle_set
      TYPE(qs_energy_type), POINTER                      :: energy
      TYPE(qs_kind_type), DIMENSION(:), POINTER          :: qs_kind_set

! -------------------------------------------------------------------------

      NULLIFY (atprop)
      CALL timeset(routineN, handle)

      CALL get_qs_env(qs_env=qs_env, atomic_kind_set=atomic_kind_set, &
                      qs_kind_set=qs_kind_set, energy=energy, atprop=atprop)

      ecore_self = 0.0_dp

      DO ikind = 1, SIZE(atomic_kind_set)
         CALL get_atomic_kind(atomic_kind_set(ikind), natom=natom)
         CALL get_qs_kind(qs_kind_set(ikind), zeff=zeff, alpha_core_charge=alpha_core_charge)
         ecore_self = ecore_self - REAL(natom, dp)*zeff**2*SQRT(alpha_core_charge)
      END DO

      energy%core_self = ecore_self/SQRT(twopi)
      IF (PRESENT(E_self_core)) THEN
         E_self_core = energy%core_self
      END IF

      IF (ASSOCIATED(atprop)) THEN
         IF (atprop%energy) THEN
            ! atomic energy
            CALL get_qs_env(qs_env=qs_env, particle_set=particle_set, &
                            local_particles=local_particles)
            natom = SIZE(particle_set)
            CALL atprop_array_init(atprop%ateself, natom)

            DO ikind = 1, SIZE(atomic_kind_set)
               nparticle_local = local_particles%n_el(ikind)
               CALL get_qs_kind(qs_kind_set(ikind), zeff=zeff, alpha_core_charge=alpha_core_charge)
               es = zeff**2*SQRT(alpha_core_charge)/SQRT(twopi)
               DO iparticle_local = 1, nparticle_local
                  iatom = local_particles%list(ikind)%array(iparticle_local)
                  atprop%ateself(iatom) = atprop%ateself(iatom) - es
               END DO
            END DO
         END IF
      END IF
      IF (PRESENT(atecc)) THEN
         ! atomic energy
         CALL get_qs_env(qs_env=qs_env, particle_set=particle_set, &
                         local_particles=local_particles)
         natom = SIZE(particle_set)
         DO ikind = 1, SIZE(atomic_kind_set)
            nparticle_local = local_particles%n_el(ikind)
            CALL get_qs_kind(qs_kind_set(ikind), zeff=zeff, alpha_core_charge=alpha_core_charge)
            es = zeff**2*SQRT(alpha_core_charge)/SQRT(twopi)
            DO iparticle_local = 1, nparticle_local
               iatom = local_particles%list(ikind)%array(iparticle_local)
               atecc(iatom) = atecc(iatom) - es
            END DO
         END DO
      END IF

      CALL timestop(handle)

   END SUBROUTINE calculate_ecore_self

! **************************************************************************************************
!> \brief Calculate the overlap and self energy of the core charge distribution for a given alpha
!>        Use a minimum image convention and double loop over all atoms
!> \param qs_env ...
!> \param alpha ...
!> \param atecc ...
!> \author  JGH
!> \version 1.0
! **************************************************************************************************
   SUBROUTINE calculate_ecore_alpha(qs_env, alpha, atecc)
      TYPE(qs_environment_type), POINTER                 :: qs_env
      REAL(KIND=dp), INTENT(IN)                          :: alpha
      REAL(KIND=dp), DIMENSION(:)                        :: atecc

      CHARACTER(len=*), PARAMETER :: routineN = 'calculate_ecore_alpha'

      INTEGER                                            :: handle, iatom, ikind, jatom, jkind, &
                                                            natom, nkind
      INTEGER, ALLOCATABLE, DIMENSION(:)                 :: kind_of
      REAL(KIND=dp)                                      :: dab, eab, fab, rootaab, zab
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:)           :: zeff
      REAL(KIND=dp), DIMENSION(3)                        :: rab
      TYPE(atomic_kind_type), DIMENSION(:), POINTER      :: atomic_kind_set
      TYPE(cell_type), POINTER                           :: cell
      TYPE(particle_type), DIMENSION(:), POINTER         :: particle_set
      TYPE(qs_kind_type), DIMENSION(:), POINTER          :: qs_kind_set

      CALL timeset(routineN, handle)

      CALL get_qs_env(qs_env=qs_env, &
                      cell=cell, &
                      atomic_kind_set=atomic_kind_set, &
                      qs_kind_set=qs_kind_set, &
                      particle_set=particle_set)
      CALL get_atomic_kind_set(atomic_kind_set=atomic_kind_set, kind_of=kind_of)
      !
      nkind = SIZE(atomic_kind_set)
      natom = SIZE(particle_set)
      ALLOCATE (zeff(nkind))
      zeff(:) = 0.0_dp
      DO ikind = 1, nkind
         CALL get_qs_kind(qs_kind_set(ikind), zeff=zeff(ikind))
      END DO

      rootaab = SQRT(0.5_dp*alpha)
      DO iatom = 1, natom
         ikind = kind_of(iatom)
         atecc(iatom) = atecc(iatom) - zeff(ikind)**2*SQRT(alpha/twopi)
         DO jatom = iatom + 1, natom
            jkind = kind_of(jatom)
            zab = zeff(ikind)*zeff(jkind)
            fab = 2.0_dp*oorootpi*zab*rootaab
            rab = particle_set(iatom)%r - particle_set(jatom)%r
            rab = pbc(rab, cell)
            dab = SQRT(SUM(rab(:)**2))
            eab = zab*erfc(rootaab*dab)/dab
            atecc(iatom) = atecc(iatom) + 0.5_dp*eab
            atecc(jatom) = atecc(jatom) + 0.5_dp*eab
         END DO
      END DO

      DEALLOCATE (zeff)

      CALL timestop(handle)

   END SUBROUTINE calculate_ecore_alpha

END MODULE qs_core_energies

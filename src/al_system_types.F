!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Type for the canonical sampling through velocity rescaling
!> \author Teodoro Laino - 09.2007 University of Zurich [tlaino]
! **************************************************************************************************
MODULE al_system_types
   USE bibliography,                    ONLY: Jones2011,&
                                              cite_reference
   USE extended_system_types,           ONLY: create_map_info_type,&
                                              map_info_type,&
                                              release_map_info_type
   USE input_section_types,             ONLY: section_vals_type,&
                                              section_vals_val_get
   USE kinds,                           ONLY: dp
   USE simpar_types,                    ONLY: simpar_type
#include "./base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE
   PUBLIC :: al_system_type, &
             al_init, &
             al_dealloc, &
             al_thermo_create

! **************************************************************************************************
   TYPE al_thermo_type
      INTEGER                                 :: degrees_of_freedom = 0
      REAL(KIND=dp)                           :: nkt = 0.0_dp
      REAL(KIND=dp)                           :: chi = 0.0_dp
      REAL(KIND=dp)                           :: mass = 0.0_dp
      REAL(KIND=dp)                           :: region_kin_energy = 0.0_dp
   END TYPE al_thermo_type

! **************************************************************************************************
   TYPE al_system_type
      INTEGER                                 :: region = 0, glob_num_al = 0, loc_num_al = 0
      REAL(KIND=dp)                           :: tau_nh = 0.0_dp, tau_langevin = 0.0_dp, dt_fact = 0.0_dp
      REAL(KIND=dp)                           :: dt = 0.0_dp
      TYPE(al_thermo_type), POINTER           :: nvt(:) => NULL()
      TYPE(map_info_type), POINTER            :: map_info => NULL()
   END TYPE al_system_type

! *** Global parameters ***
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'al_system_types'

CONTAINS

! **************************************************************************************************
!> \brief Initialize type for Adaptive Langevin (AD_LANGEVIN)
!> \param al ...
!> \param simpar ...
!> \param section ...
!> \author Noam Bernstein [noamb] 02.2012
! **************************************************************************************************
   SUBROUTINE al_init(al, simpar, section)
      TYPE(al_system_type), POINTER                      :: al
      TYPE(simpar_type), POINTER                         :: simpar
      TYPE(section_vals_type), POINTER                   :: section

      NULLIFY (al%nvt)
      NULLIFY (al%map_info)
      al%loc_num_al = 0
      al%glob_num_al = 0
      al%dt_fact = 1.0_dp
      al%dt = simpar%dt
      CALL cite_reference(Jones2011)
      CALL section_vals_val_get(section, "TIMECON_NH", r_val=al%tau_nh)
      CALL section_vals_val_get(section, "TIMECON_LANGEVIN", r_val=al%tau_langevin)
      CALL create_map_info_type(al%map_info)

   END SUBROUTINE al_init

! **************************************************************************************************
!> \brief Initialize NVT type for AD_LANGEVIN thermostat
!> \param al ...
!> \author Noam Bernstein [noamb]  02.2012
! **************************************************************************************************
   SUBROUTINE al_thermo_create(al)
      TYPE(al_system_type), POINTER                      :: al

      INTEGER                                            :: i
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:, :, :)     :: seed

      CPASSERT(ASSOCIATED(al))
      CPASSERT(.NOT. ASSOCIATED(al%nvt))

      ALLOCATE (al%nvt(al%loc_num_al))
      DO i = 1, al%loc_num_al
         al%nvt(i)%chi = 0.0_dp
      END DO
      ! Initialize the gaussian stream random number
      ALLOCATE (seed(3, 2, al%glob_num_al))

   END SUBROUTINE al_thermo_create

! **************************************************************************************************
!> \brief Deallocate type for AD_LANGEVIN thermostat
!> \param al ...
!> \author Noam Bernstein [noamb] 02.2012
! **************************************************************************************************
   SUBROUTINE al_dealloc(al)
      TYPE(al_system_type), POINTER                      :: al

      IF (ASSOCIATED(al)) THEN
         CALL al_thermo_dealloc(al%nvt)
         CALL release_map_info_type(al%map_info)
         DEALLOCATE (al)
      END IF

   END SUBROUTINE al_dealloc

! **************************************************************************************************
!> \brief Deallocate NVT type for AD_LANGEVIN thermostat
!> \param nvt ...
!> \author Noam Bernstein [noamb] 02.2012
! **************************************************************************************************
   SUBROUTINE al_thermo_dealloc(nvt)
      TYPE(al_thermo_type), DIMENSION(:), POINTER        :: nvt

      IF (ASSOCIATED(nvt)) THEN
         DEALLOCATE (nvt)
      END IF
   END SUBROUTINE al_thermo_dealloc

END MODULE al_system_types

